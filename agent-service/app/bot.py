"""Telegram-бот. Тонкий клиент: allowlist, форматирование, доставка алертов.

Ни одной формулы и ни одного порога здесь нет — всё в Snowflake. Бот умеет
три вещи: спросить, показать очередь сработавших условий и принять
подтверждение.

Про allowlist. Он проверяется первым в каждом хендлере и до вызова API.
Бот в Telegram — публичная поверхность: имя бота узнаётся перебором, и без
списка допущенных чатов доступ к риск-данным получает кто угодно.
"""

from __future__ import annotations

import asyncio
import logging

import httpx
from aiogram import Bot, Dispatcher, F
from aiogram.filters import Command
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

from .config import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(__name__)

cfg = settings()
bot = Bot(token=cfg.tg_token)
dp = Dispatcher()

HELP = (
    "Я отвечаю на вопросы к риск-витрине Plata.\n\n"
    "/ask <вопрос> — спросить (например: /ask What was our COR for April 2026?)\n"
    "/alerts — сработавшие условия governance\n"
    "/help — это сообщение\n\n"
    "Число всегда приходит вместе с SQL и именем контракта метрики. "
    "Формулу я не сочиняю: она берётся из RISK_GOV.AGENT.METRIC_CONTRACTS."
)


def allowed(message: Message) -> bool:
    return message.chat.id in cfg.tg_allowed_chats


async def call_api(path: str, method: str = "GET", **kwargs) -> httpx.Response:
    async with httpx.AsyncClient(timeout=cfg.query_timeout_s + 30) as client:
        return await client.request(
            method, f"{cfg.api_url}{path}", headers={"X-API-Key": cfg.api_key}, **kwargs
        )


def format_answer(payload: dict) -> str:
    if payload.get("error"):
        return f"Агент вернул ошибку: {payload['error']}"

    parts = [payload["answer"].strip() or "(пустой ответ)"]
    if payload.get("lint"):
        parts.append("\n⚠️ Линт по карточкам таблиц:")
        parts.extend(f"• {finding}" for finding in payload["lint"])
    tools = ", ".join(payload.get("tools") or []) or "нет"
    parts.append(f"\nИнструменты: {tools} · {payload.get('latency_s', '?')} с")
    text = "\n".join(parts)
    return text[:3900] + ("\n…" if len(text) > 3900 else "")


@dp.message(Command("start", "help"))
async def cmd_help(message: Message) -> None:
    if not allowed(message):
        log.warning("отказ чату %s", message.chat.id)
        return
    await message.answer(HELP)


@dp.message(Command("ask"))
async def cmd_ask(message: Message) -> None:
    if not allowed(message):
        log.warning("отказ чату %s", message.chat.id)
        return
    question = (message.text or "").partition(" ")[2].strip()
    if not question:
        await message.answer("После /ask нужен вопрос.")
        return

    await bot.send_chat_action(message.chat.id, "typing")
    try:
        response = await call_api(
            "/ask",
            method="POST",
            json={
                "question": question,
                "surface": "telegram",
                "user": message.from_user.username if message.from_user else str(message.chat.id),
            },
        )
        response.raise_for_status()
    except Exception as exc:  # пользователю нужен факт, а не трейсбек
        log.exception("вызов API не удался")
        await message.answer(f"Не получилось спросить агента: {exc}")
        return

    # Ответ привязывается к своему вопросу через reply, а не шлётся новым
    # сообщением. Вопрос обрабатывается 10-30 секунд, вопросы задают подряд,
    # и ответы приходят в порядке готовности — без привязки каждый ответ
    # читается как ответ на СЛЕДУЮЩИЙ вопрос. Один раз это уже произошло:
    # на вопрос про opex_predict пришёл отказ по PII от предыдущего.
    await message.reply(format_answer(response.json()))


@dp.message(Command("alerts"))
async def cmd_alerts(message: Message) -> None:
    if not allowed(message):
        return
    response = await call_api("/alerts/pending")
    alerts = response.json()
    if not alerts:
        await message.answer("Недоставленных условий нет.")
        return
    for alert in alerts:
        await send_alert(message.chat.id, alert)
    await call_api("/alerts/delivered", method="POST", json=[a["ALERT_KEY"] for a in alerts])


async def send_alert(chat_id: int, alert: dict) -> None:
    mark = "🔴" if alert["SEVERITY"] == "HIGH" else "🟡"
    text = (
        f"{mark} {alert['TITLE']}\n\n{alert['DETAIL']}\n\n"
        f"Источник: {alert['SOURCE_OBJECT']}\nСработало: {alert['FIRED_AT']}"
    )
    keyboard = InlineKeyboardMarkup(
        inline_keyboard=[[InlineKeyboardButton(text="Принял", callback_data=f"ack:{alert['ALERT_KEY']}"[:64])]]
    )
    await bot.send_message(chat_id, text[:3900], reply_markup=keyboard)


@dp.callback_query(F.data.startswith("ack:"))
async def on_ack(callback: CallbackQuery) -> None:
    if callback.message.chat.id not in cfg.tg_allowed_chats:
        return
    key = callback.data.split(":", 1)[1]
    who = callback.from_user.username or str(callback.from_user.id)
    await call_api("/alerts/ack", method="POST", params={"key": key, "who": who})
    await callback.answer("Записано")
    await callback.message.edit_reply_markup(reply_markup=None)


async def alert_pump() -> None:
    """Фоновая доставка. Условие, уже висящее неподтверждённым, второй раз не
    создаётся в самом Snowflake — гашение дребезга там, а не здесь."""
    if not cfg.tg_alert_chat:
        log.info("TG_ALERT_CHAT_ID не задан, автодоставка алертов выключена")
        return
    while True:
        try:
            response = await call_api("/alerts/pending")
            alerts = response.json()
            for alert in alerts:
                await send_alert(cfg.tg_alert_chat, alert)
            if alerts:
                await call_api("/alerts/delivered", method="POST", json=[a["ALERT_KEY"] for a in alerts])
                log.info("доставлено условий: %s", len(alerts))
        except Exception:
            log.warning("цикл доставки алертов упал, повтор через интервал", exc_info=True)
        await asyncio.sleep(cfg.alert_poll_s)


async def main() -> None:
    asyncio.create_task(alert_pump())
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
