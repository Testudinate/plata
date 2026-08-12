"""FastAPI между поверхностями и Snowflake.

Одна точка, где ставится тег запроса, режется таймаут, пишется трейс и
проверяется ответ. Вторая поверхность (MCP для Claude Desktop, веб) подключается
сюда же и получает ровно то же поведение — иначе «человек и машина ходят в одну
инфраструктуру» останется лозунгом.
"""

from __future__ import annotations

import logging

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from . import copilot
from .config import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(__name__)

app = FastAPI(title="Plata Risk Copilot", version="1.0.0")


def require_key(x_api_key: str = Header(default="")) -> None:
    if x_api_key != settings().api_key:
        raise HTTPException(status_code=401, detail="неверный ключ")


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=2000)
    surface: str = "api"
    user: str | None = None


class AskResponse(BaseModel):
    answer: str
    tools: list[str]
    sql: list[str]
    lint: list[str]
    latency_s: float
    error: str | None = None


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Живость процесса. Snowflake здесь намеренно не дёргается: health-check,
    который будит warehouse каждые тридцать секунд, стоит денег и ничего не
    проверяет — соединение поднимается на первом же реальном вопросе."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict[str, object]:
    """Готовность: одно дешёвое обращение к метаданным контекст-слоя."""
    from . import snowflake_client as sf

    rows = sf.fetch_all("SELECT COUNT(*) AS N FROM RISK_GOV.AGENT.TABLE_CARDS")
    return {"status": "ok", "table_cards": rows[0]["N"] if rows else 0}


@app.post("/ask", response_model=AskResponse, dependencies=[Depends(require_key)])
def ask(request: AskRequest) -> AskResponse:
    result = copilot.ask(request.question, surface=request.surface, user=request.user)
    if result["error"]:
        log.warning("агент вернул ошибку: %s", result["error"])
    return AskResponse(
        answer=result["text"],
        tools=result["tools"],
        sql=result["sql"],
        lint=result["lint"],
        latency_s=result["latency_s"],
        error=result["error"],
    )


@app.get("/alerts/pending", dependencies=[Depends(require_key)])
def alerts_pending(limit: int = 20) -> list[dict]:
    return copilot.pending_alerts(limit)


@app.post("/alerts/delivered", dependencies=[Depends(require_key)])
def alerts_delivered(keys: list[str]) -> dict[str, int]:
    copilot.mark_delivered(keys)
    return {"marked": len(keys)}


@app.post("/alerts/ack", dependencies=[Depends(require_key)])
def alerts_ack(key: str, who: str) -> dict[str, str]:
    copilot.acknowledge(key, who)
    return {"acknowledged": key}
