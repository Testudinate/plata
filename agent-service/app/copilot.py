"""Вызов агента Snowflake и проверка того, что он выдал.

Агент живёт в аккаунте (`RISK_GOV.AGENT.RISK_COPILOT`) и сам ходит в
семантическую вью, в Cortex Search и в SQL. Здесь — только обвязка:
разобрать ответ, прогнать линт по карточкам таблиц, записать прогон.

Про линт. `PITFALLS.DETECTION_SQL` проверяет свойство ДАННЫХ («ловушка на месте»),
а не правильность конкретного ответа. Ответ проверяется другим: в
`TABLE_CARDS.MANDATORY_FILTERS` записаны фильтры, без которых ответ не неполон,
а неверен. Если агент тронул объект и не поставил его обязательный фильтр —
это находка, и её видно до того, как число уедет в чат.
"""

from __future__ import annotations

import json
import logging
import re
import time
from typing import Any

from . import snowflake_client as sf

log = logging.getLogger(__name__)

_SQL_FENCE = re.compile(r"```sql\s+(.*?)```", re.DOTALL | re.IGNORECASE)
_WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")


def _agent_request(question: str) -> str:
    return json.dumps(
        {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]},
        ensure_ascii=False,
    )


def _parse_response(raw: str) -> dict[str, Any]:
    """Разбор ответа агента: текст, использованные инструменты, SQL."""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {"text": raw, "tools": [], "sql": [], "error": "ответ агента не разобрался как JSON"}

    if isinstance(payload, dict) and payload.get("code"):
        return {"text": "", "tools": [], "sql": [], "error": payload.get("message", "ошибка агента")}

    texts: list[str] = []
    tools: list[str] = []
    sql: list[str] = []

    for item in payload.get("content", []):
        kind = item.get("type")
        if kind == "text" and item.get("text"):
            texts.append(item["text"])
        elif kind == "tool_use":
            spec = item.get("tool_use", {})
            tools.append(spec.get("name", "?"))
            payload_in = spec.get("input") or {}
            for key in ("sql", "query", "statement"):
                if isinstance(payload_in.get(key), str):
                    sql.append(payload_in[key])

    answer = "\n".join(t for t in texts if t.strip())
    sql.extend(match.strip() for match in _SQL_FENCE.findall(answer))
    return {"text": answer, "tools": tools, "sql": sql, "error": None}


def _table_cards() -> list[dict[str, Any]]:
    return sf.fetch_all(
        """
        SELECT object_name, mandatory_filters, product_filter_column, do_not
        FROM RISK_GOV.AGENT.TABLE_CARDS
        WHERE mandatory_filters IS NOT NULL AND mandatory_filters <> 'none'
        """
    )


def lint_sql(statements: list[str], cards: list[dict[str, Any]] | None = None) -> list[str]:
    """Проверка выданного SQL против обязательных фильтров карточек таблиц."""
    if not statements:
        return []
    cards = cards if cards is not None else _table_cards()
    findings: list[str] = []

    for statement in statements:
        normalized = " ".join(statement.split()).upper()
        for card in cards:
            obj = (card["OBJECT_NAME"] or "").upper()
            short = obj.rsplit(".", 1)[-1]
            if short and short not in normalized:
                continue
            required = card["MANDATORY_FILTERS"] or ""
            # Из «account_type = 'CC'» берём опорные токены: колонку и значение.
            tokens = [tok.upper() for tok in _WORD.findall(required) if len(tok) > 2]
            missing = [tok for tok in tokens if tok not in normalized]
            if missing:
                findings.append(
                    f"{obj}: в запросе нет обязательного фильтра «{required}» "
                    f"(не найдено: {', '.join(sorted(set(missing)))})"
                )
    return findings


def ask(question: str, surface: str = "api", user: str | None = None) -> dict[str, Any]:
    """Задать вопрос агенту, проверить ответ, записать прогон."""
    from .config import settings

    cfg = settings()
    tag = {"app": "plata-copilot", "surface": surface, "user": user or "anonymous"}
    started = time.monotonic()

    rows = sf.fetch_all(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(%s, %s) AS RESPONSE",
        (cfg.agent_name, _agent_request(question)),
        tag=tag,
    )
    raw = rows[0]["RESPONSE"] if rows else ""
    parsed = _parse_response(raw)
    parsed["latency_s"] = round(time.monotonic() - started, 2)
    parsed["lint"] = lint_sql(parsed["sql"]) if not parsed["error"] else []

    try:
        sf.write(
            """
            INSERT INTO RISK_GOV.AGENT.AGENT_RUN_LOG (SURFACE, QUESTION, RESPONSE)
            SELECT %s, %s, %s
            """,
            (surface, question, raw),
            tag=tag,
        )
    except Exception:  # журнал прогонов не имеет права уронить ответ пользователю
        log.warning("не удалось записать прогон в AGENT_RUN_LOG", exc_info=True)

    return parsed


def pending_alerts(limit: int = 20) -> list[dict[str, Any]]:
    return sf.fetch_all(
        """
        SELECT fired_at, alert_key, severity, title, detail, source_object
        FROM RISK_GOV.DQ.ALERT_LOG
        WHERE delivered_at IS NULL
        ORDER BY IFF(severity = 'HIGH', 0, 1), fired_at
        LIMIT %s
        """,
        (limit,),
        tag={"app": "plata-copilot", "surface": "alerts"},
    )


def mark_delivered(alert_keys: list[str]) -> None:
    if not alert_keys:
        return
    placeholders = ", ".join(["%s"] * len(alert_keys))
    sf.write(
        f"""
        UPDATE RISK_GOV.DQ.ALERT_LOG SET delivered_at = SYSDATE()
        WHERE delivered_at IS NULL AND alert_key IN ({placeholders})
        """,
        tuple(alert_keys),
        tag={"app": "plata-copilot", "surface": "alerts"},
    )


def acknowledge(alert_key: str, who: str) -> None:
    sf.write(
        "UPDATE RISK_GOV.DQ.ALERT_LOG SET ack_by = %s WHERE alert_key = %s AND ack_by IS NULL",
        (who, alert_key),
        tag={"app": "plata-copilot", "surface": "alerts"},
    )
