"""Выгрузка журнала вопросов и ответов в читаемый документ.

Журнал `RISK_GOV.AGENT.AGENT_RUN_LOG` хранит ПОЛНЫЙ ответ агента в JSON —
вместе с шагами использования инструментов и промежуточными результатами.
Для разбора это правильно, для чтения человеком — нет: 25 КБ на вопрос.

Здесь тот же JSON превращается в стенограмму: вопрос, ответ, какими
инструментами он получен, какой SQL был выполнен. Именно в таком виде
диалог годится как приложение к ответу на задание — рецензент видит не
описание того, что агент умеет, а протокол того, что он ответил.

Использование:
    python -m app.export_log --out /srv/data/transcript.md
    python -m app.export_log --surface telegram --days 7 --format jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from typing import Any

from . import copilot
from . import snowflake_client as sf


def fetch(surface: str | None, days: int, limit: int) -> list[dict[str, Any]]:
    where = ["RUN_AT >= DATEADD('day', %s, CURRENT_TIMESTAMP())"]
    params: list[Any] = [-abs(days)]
    if surface:
        where.append("SURFACE = %s")
        params.append(surface)
    params.append(limit)
    return sf.fetch_all(
        f"""
        SELECT RUN_AT, SURFACE, QUESTION, RESPONSE
        FROM RISK_GOV.AGENT.AGENT_RUN_LOG
        WHERE {' AND '.join(where)}
        ORDER BY RUN_AT
        LIMIT %s
        """,
        tuple(params),
        tag={"app": "plata-copilot", "surface": "export"},
    )


def to_markdown(rows: list[dict[str, Any]], generated_at: str) -> str:
    out: list[str] = [
        "# Agent transcript — Plata Risk Copilot",
        "",
        f"Runs: {len(rows)}. Exported {generated_at}.",
        "",
        "Source: `RISK_GOV.AGENT.AGENT_RUN_LOG`. Every answer below was produced",
        "by `RISK_GOV.AGENT.RISK_COPILOT` against live data, under role",
        "`LLM_AGENT_RO` (read-only, no PII). The `Tools` line matters as much as",
        "the answer: a number obtained without `cor_metrics` came from the model,",
        "not from the metric contract.",
        "",
        "---",
        "",
    ]

    for index, row in enumerate(rows, start=1):
        parsed = copilot._parse_response(row["RESPONSE"] or "")
        stamp = row["RUN_AT"].strftime("%Y-%m-%d %H:%M") if row["RUN_AT"] else "?"
        tools = ", ".join(parsed["tools"]) or "none"

        out += [
            f"## {index}. {row['QUESTION']}",
            "",
            f"*{stamp} · surface: {row['SURFACE']} · tools: {tools}*",
            "",
        ]

        if parsed["error"]:
            out += [f"> Failed: {parsed['error']}", ""]
        else:
            out += [parsed["text"].strip() or "_(empty answer)_", ""]

            # SQL из ответа уже внутри текста в блоках ```sql; отдельно
            # выводим только тот, что агент выполнял через инструмент —
            # его в тексте может не быть.
            tool_sql = [s for s in parsed["sql"] if s.strip() not in (parsed["text"] or "")]
            if tool_sql:
                out += ["**SQL executed by the agent:**", ""]
                for statement in tool_sql:
                    out += ["```sql", statement.strip(), "```", ""]

        out += ["---", ""]

    return "\n".join(out)


def to_jsonl(rows: list[dict[str, Any]]) -> str:
    lines = []
    for row in rows:
        parsed = copilot._parse_response(row["RESPONSE"] or "")
        lines.append(json.dumps({
            "run_at": row["RUN_AT"].isoformat() if row["RUN_AT"] else None,
            "surface": row["SURFACE"],
            "question": row["QUESTION"],
            "answer": parsed["text"],
            "tools": parsed["tools"],
            "sql": parsed["sql"],
            "error": parsed["error"],
        }, ensure_ascii=False))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Выгрузка диалогов с агентом")
    parser.add_argument("--out", default="/srv/data/transcript.md", help="куда писать")
    parser.add_argument("--format", choices=["md", "jsonl"], default="md")
    parser.add_argument("--surface", help="telegram | eval | api | sql — по умолчанию все")
    parser.add_argument("--days", type=int, default=30, help="за сколько дней назад")
    parser.add_argument("--limit", type=int, default=500)
    args = parser.parse_args()

    rows = fetch(args.surface, args.days, args.limit)
    if not rows:
        print("в журнале нет записей под эти условия", file=sys.stderr)
        return 1

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    body = to_markdown(rows, stamp) if args.format == "md" else to_jsonl(rows)

    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(body)

    surfaces = sorted({row["SURFACE"] for row in rows})
    print(f"записей: {len(rows)} ({', '.join(surfaces)}) → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
