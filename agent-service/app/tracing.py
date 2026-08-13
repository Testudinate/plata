"""Трейсинг в self-hosted Langfuse. Best-effort и только он.

Дисциплина повторяет `hermes-memory/src/langfuse_trace.py`, потому что она уже
оплачена ошибками:

* трейсинг **никогда не роняет и не тормозит запрос** — все вызовы обёрнуты,
  SDK копит события и шлёт фоновым потоком;
* **выключается целиком** без ключей и без пакета: `git pull` без пересборки
  образа не должен ронять сервис;
* **eval-трафик помечается тегом** `eval` — иначе ночные прогоны забьют
  Langfuse так же, как когда-то забили журнал поиска.

Что здесь отвечает на вопрос, на который не отвечает счёт Snowflake: не
«сколько потрачено», а «на что». Ответ агента несёт разбивку токенов по
шагам — сколько ушло в кэш-чтение против свежего контекста, сколько на
выход, какая модель оркестрации. Из счёта видно 9.6 кредита; из трейса видно,
что 82% входных токенов вопроса — это чтение кэша, то есть контекст-слой и
семантическая модель, которые едут в каждый прогон.

Про деньги. Ставки `CORTEX_AGENTS` в `RATE_SHEET_DAILY` нет — Snowflake их
пока не тарифицирует отдельной строкой. Поэтому стоимость проставляется
ТОЛЬКО если задан `CORTEX_USD_PER_1M_TOKENS`; иначе поле пустое. Показать
выдуманную цену хуже, чем не показать никакой: $0.00 неотличимо от «вызов
ничего не стоил».
"""

from __future__ import annotations

import logging
import os
from contextlib import contextmanager
from typing import Any, Iterator

log = logging.getLogger(__name__)

try:
    from langfuse import get_client  # type: ignore
    _HAS_SDK = True
except Exception:  # пакет не установлен — трейсинг просто выключен
    _HAS_SDK = False

_client: Any = None
_checked = False


def _usd_per_1m() -> float | None:
    raw = os.environ.get("CORTEX_USD_PER_1M_TOKENS", "").strip()
    try:
        return float(raw) if raw else None
    except ValueError:
        return None


def client() -> Any:
    """Клиент Langfuse или None. Инициализация одна на процесс."""
    global _client, _checked
    if _checked:
        return _client
    _checked = True

    from .config import settings

    cfg = settings()
    if not _HAS_SDK or not cfg.tracing_enabled:
        log.info("трейсинг выключен (пакет: %s, ключи: %s)", _HAS_SDK, cfg.tracing_enabled)
        return None
    try:
        _client = get_client()
        log.info("трейсинг включён, host=%s", cfg.langfuse_host)
    except Exception:
        log.warning("Langfuse не инициализировался, продолжаем без трейсинга", exc_info=True)
        _client = None
    return _client


def token_usage(response_json: dict[str, Any]) -> dict[str, int]:
    """Разбор metadata.usage из ответа агента.

    Форма ответа Cortex: metadata.usage.tokens_consumed — список записей по
    моделям, у каждой input_tokens {cache_read, cache_write, uncached, total}
    и output_tokens {total}. Кэш-чтение выделяем отдельно: это и есть цена
    контекст-слоя, который едет в каждый прогон.
    """
    out = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
    try:
        entries = response_json.get("metadata", {}).get("usage", {}).get("tokens_consumed", []) or []
        for entry in entries:
            inp = entry.get("input_tokens") or {}
            out["input"] += int(inp.get("total") or 0)
            out["cache_read"] += int(inp.get("cache_read") or 0)
            out["cache_write"] += int(inp.get("cache_write") or 0)
            out["output"] += int((entry.get("output_tokens") or {}).get("total") or 0)
    except Exception:
        log.debug("не удалось разобрать usage из ответа агента", exc_info=True)
    return out


def model_name(response_json: dict[str, Any]) -> str:
    try:
        entries = response_json.get("metadata", {}).get("usage", {}).get("tokens_consumed", []) or []
        return entries[0].get("model_name") or "unknown"
    except Exception:
        return "unknown"


@contextmanager
def question(surface: str, user: str | None, text: str) -> Iterator[Any]:
    """Корневой observation на один вопрос. Без Langfuse — пустой контекст."""
    lf = client()
    if lf is None:
        yield None
        return

    span = None
    try:
        span = lf.start_span(name="copilot.ask", input={"question": text})
        # Теги ставятся на трейс: без них eval-прогоны неотличимы от живых
        # вопросов, и через неделю в Langfuse будет 90% синтетики.
        lf.update_current_trace(
            user_id=user or "anonymous",
            session_id=f"{surface}:{user or 'anonymous'}",
            tags=[surface] + (["eval"] if surface == "eval" else []),
        )
    except Exception:
        log.debug("не удалось открыть трейс", exc_info=True)
        span = None

    try:
        yield span
    finally:
        if span is not None:
            try:
                span.end()
            except Exception:
                log.debug("не удалось закрыть трейс", exc_info=True)


def record_agent_run(span: Any, response_json: dict[str, Any], parsed: dict[str, Any], latency_s: float) -> None:
    """Вложенный generation: сам прогон агента с токенами и инструментами."""
    lf = client()
    if lf is None or span is None:
        return
    try:
        usage = token_usage(response_json)
        rate = _usd_per_1m()
        total_tokens = usage["input"] + usage["output"]
        cost = {"total": total_tokens / 1_000_000 * rate} if rate and total_tokens else None

        generation = lf.start_generation(
            name="cortex.data_agent_run",
            model=model_name(response_json),
            input={"tools_available": ["cor_metrics", "risk_docs", "sql_exec"]},
        )
        generation.update(
            output={
                "answer": (parsed.get("text") or "")[:4000],
                "tools_used": parsed.get("tools"),
                "sql": parsed.get("sql"),
                "lint_findings": parsed.get("lint"),
            },
            usage_details={
                "input": usage["input"],
                "output": usage["output"],
                "cache_read_input_tokens": usage["cache_read"],
                "cache_creation_input_tokens": usage["cache_write"],
            },
            **({"cost_details": cost} if cost else {}),
            metadata={"latency_s": latency_s, "cost_source": "env rate" if cost else "не задана"},
        )
        generation.end()
    except Exception:
        log.debug("не удалось записать generation", exc_info=True)


def flush() -> None:
    """Дожать очередь. Нужно только скриптам, которые сразу завершаются."""
    lf = client()
    if lf is None:
        return
    try:
        lf.flush()
    except Exception:
        log.debug("flush не удался", exc_info=True)
