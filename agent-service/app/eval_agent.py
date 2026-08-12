"""Регресс агента по золотому набору RISK_GOV.AGENT.EVAL_QUESTIONS.

Зачем это здесь, а не в нативных Evaluations Snowflake: оценка агента
инструментом того же вендора, которым агент сделан, слабее как свидетельство.
Нативные Evaluations берём вторым мнением, вердикт держим у себя.

Дисциплина повторяет `hermes-memory/scripts/eval_retrieval.py`:
  --save baseline.json      снять базу до изменения
  --compare baseline.json   сравнить после; exit 2 при деградации

Разбивка по DIFFICULTY обязательна. Общая точность упирается в потолок на
лёгких вопросах и прячет провал на hard — на другом наборе это уже ловилось.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from typing import Any

from . import copilot
from . import snowflake_client as sf

NUMBER = re.compile(r"-?\d+(?:[.,]\d+)?")

# Вопросы, где проверяется поведение, а не число. Ключевые слова — признак
# правильного поведения; они намеренно широкие: важно, что агент отказал или
# перенаправил, а не какими словами.
BEHAVIOURAL = {
    "Q15": ("no access", "not able", "cannot", "won't", "нет доступа"),
    "Q16": ("npv_gen5_details", "dropped", "no longer exists"),
}


def golden_set() -> list[dict[str, Any]]:
    return sf.fetch_all(
        """
        SELECT question_id, question, difficulty, pitfall_tested, expected_value, tolerance
        FROM RISK_GOV.AGENT.EVAL_QUESTIONS
        ORDER BY question_id
        """
    )


def _numbers(text: str) -> list[float]:
    out = []
    for raw in NUMBER.findall(text):
        try:
            out.append(float(raw.replace(",", ".")))
        except ValueError:
            continue
    return out


def judge(case: dict[str, Any], answer: dict[str, Any]) -> dict[str, Any]:
    qid = case["QUESTION_ID"]
    verdict: dict[str, Any] = {
        "question_id": qid,
        "difficulty": case["DIFFICULTY"],
        "latency_s": answer["latency_s"],
        "tools": answer["tools"],
        "lint_findings": len(answer["lint"]),
        "error": answer["error"],
    }
    text = (answer["text"] or "").lower()

    if answer["error"]:
        verdict.update(passed=False, reason="агент вернул ошибку")
        return verdict

    if qid in BEHAVIOURAL:
        hit = any(marker in text for marker in BEHAVIOURAL[qid])
        verdict.update(passed=hit, reason="ожидаемое поведение" if hit else "поведение не подтверждено")
        return verdict

    expected_raw = (case["EXPECTED_VALUE"] or "").strip()
    try:
        expected = float(expected_raw.replace(",", "."))
    except ValueError:
        hit = expected_raw.lower() in text
        verdict.update(passed=hit, reason="сверка по строке")
        return verdict

    tolerance = float(case["TOLERANCE"] or 0.01)
    found = _numbers(answer["text"] or "")
    close = [n for n in found if abs(n - expected) <= max(abs(expected) * tolerance, tolerance)]
    verdict.update(
        passed=bool(close),
        expected=expected,
        got=close[0] if close else (found[0] if found else None),
        reason="число в допуске" if close else "ожидаемого числа в ответе нет",
    )
    return verdict


def run() -> dict[str, Any]:
    cases = golden_set()
    started = time.monotonic()
    verdicts = []
    for case in cases:
        answer = copilot.ask(case["QUESTION"], surface="eval", user="eval-runner")
        verdicts.append(judge(case, answer))

    passed = [v for v in verdicts if v["passed"]]
    by_difficulty: dict[str, dict[str, int]] = {}
    for verdict in verdicts:
        bucket = by_difficulty.setdefault(verdict["difficulty"], {"total": 0, "passed": 0})
        bucket["total"] += 1
        bucket["passed"] += int(verdict["passed"])

    latencies = sorted(v["latency_s"] for v in verdicts)
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))] if latencies else 0

    return {
        "total": len(verdicts),
        "passed": len(passed),
        "accuracy": round(len(passed) / len(verdicts), 4) if verdicts else 0,
        "lint_findings": sum(v["lint_findings"] for v in verdicts),
        "p95_latency_s": p95,
        "wall_clock_s": round(time.monotonic() - started, 1),
        "by_difficulty": {
            key: {**value, "accuracy": round(value["passed"] / value["total"], 4)}
            for key, value in sorted(by_difficulty.items())
        },
        "verdicts": verdicts,
    }


def compare(current: dict[str, Any], baseline_path: str, epsilon: float) -> int:
    with open(baseline_path, encoding="utf-8") as handle:
        baseline = json.load(handle)

    failures = []
    if current["accuracy"] + epsilon < baseline["accuracy"]:
        failures.append(f"общая точность {baseline['accuracy']} → {current['accuracy']}")
    for level, base in baseline.get("by_difficulty", {}).items():
        now = current["by_difficulty"].get(level)
        if now and now["accuracy"] + epsilon < base["accuracy"]:
            failures.append(f"{level}: {base['accuracy']} → {now['accuracy']}")
    if current["lint_findings"] > baseline.get("lint_findings", 0):
        failures.append(
            f"срабатываний линта {baseline.get('lint_findings', 0)} → {current['lint_findings']}"
        )

    if failures:
        print("ДЕГРАДАЦИЯ:", "; ".join(failures), file=sys.stderr)
        return 2
    print("деградации нет")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Регресс риск-агента по золотому набору")
    parser.add_argument("--save", metavar="FILE", help="сохранить результат как baseline")
    parser.add_argument("--compare", metavar="FILE", help="сравнить с baseline, exit 2 при деградации")
    parser.add_argument("--epsilon", type=float, default=0.0, help="допуск дрожания точности")
    args = parser.parse_args()

    result = run()
    print(json.dumps({k: v for k, v in result.items() if k != "verdicts"}, ensure_ascii=False, indent=2))
    for verdict in result["verdicts"]:
        if not verdict["passed"]:
            print(f"  ✗ {verdict['question_id']} ({verdict['difficulty']}): {verdict['reason']}")

    if args.save:
        with open(args.save, "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
        print(f"baseline сохранён в {args.save}")

    if args.compare:
        return compare(result, args.compare, args.epsilon)
    return 0


if __name__ == "__main__":
    sys.exit(main())
