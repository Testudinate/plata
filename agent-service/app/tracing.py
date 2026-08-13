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
from contextlib import ExitStack, contextmanager
from typing import Any, Iterator

log = logging.getLogger(__name__)

try:
    from langfuse import get_client  # type: ignore
    _HAS_SDK = True
except Exception:  # пакет не установлен — трейсинг просто выключен
    _HAS_SDK = False

_client: Any = None
_checked = False
_warned = False
_tagging_noted = False


def _note_tagging(mechanism: str) -> None:
    """Один раз сказать в лог, чем размечается трейс. Дальше молчим."""
    global _tagging_noted
    if not _tagging_noted:
        _tagging_noted = True
        log.info("разметка трейса: %s", mechanism)


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
    """Корневой observation на один вопрос. Без Langfuse — пустой контекст.

    ПРО API 4.x, дважды поправленный. В модели данных v4 трейса как отдельной
    сущности нет: трейс — это корневой observation. Отсюда два следствия,
    на которых я споткнулся по очереди:

    1. Метод один — `start_as_current_observation(as_type=...)`. Ни
       `start_span`, ни `start_as_current_span` в 4.14 не существует.
    2. `user_id`, `session_id` и теги относятся к трейсу, а не к observation,
       поэтому ставятся `propagate_attributes` — контекстом, который
       наследуют все вложенные шаги. `update_current_trace` в этой ветке нет.

    Оба факта записаны в hermes-memory/CLAUDE.md и стоили там отдельной
    итерации. Здесь они стоили ещё одной.
    """
    lf = client()
    if lf is None:
        yield None
        return

    tags = [surface] + (["eval"] if surface == "eval" else [])
    trace_attrs = {
        "user_id": user or "anonymous",
        "session_id": f"{surface}:{user or 'anonymous'}",
        "tags": tags,
    }
    attrs = getattr(lf, "propagate_attributes", None)

    try:
        with ExitStack() as stack:
            if attrs is not None:
                try:
                    stack.enter_context(attrs(**trace_attrs))
                except Exception:
                    log.debug("propagate_attributes не принял атрибуты", exc_info=True)

            span = stack.enter_context(lf.start_as_current_observation(
                name=f"copilot.ask:{surface}", as_type="span", input={"question": text},
            ))

            # Второй путь. propagate_attributes задаёт контекст, но теги на
            # трейсе от него не появились — в v4 трейс это корневой
            # observation, и разметку принимает он сам через update_trace.
            # Делаем оба и логируем, какой сработал: молчаливое «тегов нет»
            # уже стоило круга диагностики.
            update_trace = getattr(span, "update_trace", None)
            if update_trace is not None:
                try:
                    update_trace(name=f"copilot:{surface}", **trace_attrs)
                    _note_tagging("span.update_trace")
                except Exception:
                    log.debug("span.update_trace не принял атрибуты", exc_info=True)
            elif attrs is None:
                _note_tagging("нет ни одного механизма разметки трейса")

            yield span
    except Exception:
        # Первый отказ — WARNING с трейсбеком, дальше DEBUG. Молчаливая
        # деградация здесь опаснее самой ошибки: трейсов нет, в логе чисто,
        # и причина ищется в сети и ключах, а не в коде.
        global _warned
        if not _warned:
            _warned = True
            log.warning("трейс не открылся, работаем без него — проверьте python -m app.tracing", exc_info=True)
        else:
            log.debug("трейс не открылся", exc_info=True)
        yield None


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

        with lf.start_as_current_observation(
            name="cortex.data_agent_run",
            as_type="generation",
            model=model_name(response_json),
            input={"tools_available": ["cor_metrics", "risk_docs", "sql_exec"]},
        ) as generation:
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
    except Exception:
        global _warned
        if not _warned:
            _warned = True
            log.warning("generation не записался, трейс будет неполным", exc_info=True)
        else:
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


def selftest() -> int:
    """Диагностика в одну команду: python -m app.tracing

    Отвечает по порядку на все вопросы, которые задаёшь, когда трейсов нет:
    установлен ли пакет, заданы ли ключи, доступен ли хост, доезжает ли
    пробный трейс. Каждая строка — отдельная гипотеза, а не «что-то не так».
    """
    import urllib.request

    from .config import settings

    cfg = settings()
    print(f"1. пакет langfuse:      {'установлен' if _HAS_SDK else 'НЕТ — pip не поставил, пересоберите образ'}")
    print(f"2. LANGFUSE_HOST:       {cfg.langfuse_host or 'ПУСТО'}")
    print(f"3. ключи заданы:        {'да' if cfg.tracing_enabled else 'НЕТ — public/secret пустые'}")

    if cfg.langfuse_host:
        try:
            code = urllib.request.urlopen(cfg.langfuse_host.rstrip("/") + "/api/public/health", timeout=5).status
            print(f"4. хост отвечает:       HTTP {code}")
        except Exception as exc:
            print(f"4. хост отвечает:       НЕТ — {exc}")
            print("   внутри контейнера 127.0.0.1 — это его собственная петля;")
            print("   идти надо по имени контейнера в сети llm-shared")

    lf = client()
    if lf is None:
        print("5. пробный трейс:       пропущен, клиент не создан")
        return 1

    try:
        attrs = getattr(lf, "propagate_attributes", None)
        with ExitStack() as stack:
            if attrs is not None:
                stack.enter_context(attrs(user_id="selftest", session_id="selftest", tags=["selftest"]))
            span = stack.enter_context(lf.start_as_current_observation(
                name="plata-copilot:selftest", as_type="span", input={"probe": "plata-copilot"},
            ))
            span.update(output={"ok": True})
        lf.flush()
        print("5. пробный трейс:       отправлен и дожат (flush)")
        print("   ищите трейс с именем plata-copilot:selftest и тегом selftest")
        print("   если его нет в интерфейсе — версия сервера не совпадает с SDK 4.x:")
        print("   docker inspect langfuse-server --format '{{.Config.Image}}'")
        return 0
    except Exception as exc:
        print(f"5. пробный трейс:       ОШИБКА — {exc}")
        return 2


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    sys.exit(selftest())
