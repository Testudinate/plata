"""FastAPI между поверхностями и Snowflake.

Одна точка, где ставится тег запроса, режется таймаут, пишется трейс и
проверяется ответ. Вторая поверхность (MCP для Claude Desktop, веб) подключается
сюда же и получает ровно то же поведение — иначе «человек и машина ходят в одну
инфраструктуру» останется лозунгом.
"""

from __future__ import annotations

import logging

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
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
def readyz() -> JSONResponse:
    """Готовность: одно дешёвое обращение к метаданным контекст-слоя.

    Проверка готовности обязана говорить, ПОЧЕМУ не готова. Первая редакция
    отдавала голый 500 на любую ошибку соединения, и «404 на login-request»
    (неверное имя аккаунта) выглядело точно так же, как «пользователя нет» и
    как «ключ не подошёл» — то есть никак.
    """
    from . import snowflake_client as sf

    try:
        rows = sf.fetch_all("SELECT COUNT(*) AS N FROM RISK_GOV.AGENT.TABLE_CARDS")
    except Exception as exc:
        log.warning("проверка готовности не прошла: %s", exc)
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "reason": _diagnose(exc), "detail": str(exc)[:500]},
        )
    return JSONResponse(content={"status": "ok", "table_cards": rows[0]["N"] if rows else 0})


def _diagnose(exc: Exception) -> str:
    """Перевод типовых отказов Snowflake в понятное действие."""
    text = str(exc)
    if "login-request" in text and "404" in text:
        return ("SNOWFLAKE_ACCOUNT задан неверно: это account locator, а не идентификатор. "
                "Нужна форма <организация>-<аккаунт> из URL Snowsight")
    if "250001" in text or "Incorrect username or password" in text:
        return "Пользователь не найден или ключ не подошёл: проверьте CREATE USER и ALTER USER ... SET RSA_PUBLIC_KEY"
    if "JWT token is invalid" in text or "390144" in text:
        return "Публичный ключ на пользователе не соответствует приватному в контейнере"
    if "Role" in text and "not exist" in text:
        return "Роль не выдана пользователю: GRANT ROLE LLM_AGENT_RO TO USER PLATA_COPILOT_SVC"
    if "Permission denied" in text or "Errno 13" in text:
        return "Контейнер не может прочитать ключ: chown 10001:10001 на файле ключа"
    if "does not exist or not authorized" in text:
        return "Роль подключилась, но не видит объект: не хватает грантов из части B"
    return "неопознанный отказ, смотрите detail"


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
