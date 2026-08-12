"""Соединения со Snowflake. Две личности, а не одна.

Первая мысль была сделать одно соединение под `LLM_AGENT_RO` и им же писать
журнал прогонов. Так нельзя, и это выяснилось не на ревью, а на первом же
`INSERT`: роль read-only, плюс на сессии стоит `CORTEX_CLIENT_READ_ONLY`,
который по описанию самого параметра **cannot be disabled once set**.

Разводить пришлось не потому, что мешает механизм, а потому что это и есть
правильная граница:

* `reader` — `LLM_AGENT_RO`, отвечает на вопросы, видит витрины и контекст-слой,
  писать не может ничем и никуда. Плюс `CORTEX_CLIENT_READ_ONLY` как второй слой
  поверх прав роли: права — настоящая граница, но продублированная на клиенте
  переживает ошибку в грантах.
* `writer` — `COPILOT_WRITER`, умеет ровно два действия: `INSERT` в
  `AGENT.AGENT_RUN_LOG` и `UPDATE` двух колонок `DQ.ALERT_LOG`. Риск-данных не
  видит вовсе.

Личность, которая отвечает на вопросы, не может ничего записать; личность,
которая ведёт журнал, не может ничего прочитать. `QUERY_TAG` ставится всегда:
без него аудит отвечает «агент спросил», с ним — «кто попросил и каким вопросом».
"""

from __future__ import annotations

import json
import logging
from contextlib import contextmanager
from typing import Any, Iterator, Literal

import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from .config import settings

log = logging.getLogger(__name__)

Mode = Literal["reader", "writer"]

_key_cache: bytes | None = None


def _private_key() -> bytes:
    global _key_cache
    if _key_cache is None:
        cfg = settings()
        passphrase = cfg.sf_private_key_passphrase.encode() if cfg.sf_private_key_passphrase else None
        with open(cfg.sf_private_key_path, "rb") as handle:
            key = serialization.load_pem_private_key(handle.read(), password=passphrase, backend=default_backend())
        _key_cache = key.private_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    return _key_cache


@contextmanager
def session(tag: dict[str, Any] | None = None, mode: Mode = "reader") -> Iterator[Any]:
    cfg = settings()
    role = cfg.sf_role if mode == "reader" else cfg.sf_writer_role
    conn = snowflake.connector.connect(
        account=cfg.sf_account,
        user=cfg.sf_user,
        role=role,
        warehouse=cfg.sf_warehouse,
        private_key=_private_key(),
        client_session_keep_alive=False,
        network_timeout=cfg.query_timeout_s,
    )
    try:
        cur = conn.cursor()

        # Параметры сессии ставятся ПО ОДНОМУ и каждый со своим сообщением.
        # Иначе отказ любого из них выглядит как один и тот же 399517
        # (0A000, feature not supported) без указания виновника — на этом
        # уже потерян один круг диагностики.
        #
        # Ни один из них не является границей безопасности: настоящий запрет
        # записи — это права роли LLM_AGENT_RO. Поэтому отказ логируется и
        # работа продолжается, но никогда не проглатывается молча.
        # ПОРЯДОК ЗДЕСЬ — НЕ СТИЛЬ, А УСЛОВИЕ РАБОТОСПОСОБНОСТИ.
        # CORTEX_CLIENT_READ_ONLY разрешает в сессии только SELECT, EXPLAIN,
        # SHOW и DESCRIBE. ALTER SESSION в этот список не входит, поэтому
        # выставленный первым он глушит всё, что идёт после: и таймаут, и
        # QUERY_TAG. Симптом обманчивый — 399517 (0A000, feature not supported)
        # выглядит как ограничение аккаунта, хотя тот же оператор в обычной
        # сессии проходит. Read-only ставится ПОСЛЕДНИМ и только для reader.
        setup: list[tuple[str, tuple[Any, ...], str]] = [(
            f"ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = {cfg.query_timeout_s}", (),
            "таймаут запроса не выставлен; долгий запрос не будет прерван сам",
        )]
        if tag:
            setup.append((
                "ALTER SESSION SET QUERY_TAG = %s", (json.dumps(tag, ensure_ascii=False),),
                "QUERY_TAG не выставлен; аудит покажет 'агент спросил' без указания, кто попросил",
            ))
        if mode == "reader":
            setup.append((
                "ALTER SESSION SET CORTEX_CLIENT_READ_ONLY = TRUE", (),
                "клиентское дублирование read-only недоступно; запрет записи держится правами роли",
            ))

        for statement, params, consequence in setup:
            name = statement.split("SET", 1)[1].split("=")[0].strip()
            try:
                cur.execute(statement, params)
            except Exception as exc:
                log.warning("параметр сессии %s не принят (%s) — %s", name, exc, consequence)

        cur.close()
        yield conn
    finally:
        conn.close()


def fetch_all(sql: str, params: tuple[Any, ...] = (), tag: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    with session(tag, mode="reader") as conn:
        cur = conn.cursor(snowflake.connector.DictCursor)
        try:
            cur.execute(sql, params)
            return list(cur.fetchall())
        finally:
            cur.close()


def write(sql: str, params: tuple[Any, ...] = (), tag: dict[str, Any] | None = None) -> None:
    """Запись журнала. Только под ролью writer и только по объектам журнала."""
    with session(tag, mode="writer") as conn:
        cur = conn.cursor()
        try:
            cur.execute(sql, params)
        finally:
            cur.close()
