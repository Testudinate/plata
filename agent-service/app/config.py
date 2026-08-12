"""Настройки. Fail-closed: без обязательного секрета сервис не стартует.

Дефолтных значений для секретов здесь нет и быть не должно — пустой дефолт
однажды превращается в «работает, но без защиты», и это незаметно.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


class ConfigError(RuntimeError):
    pass


def _required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ConfigError(f"{name} не задан — сервис не стартует без него")
    return value


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


def _chat_allowlist() -> frozenset[int]:
    raw = os.environ.get("TG_ALLOWED_CHAT_IDS", "").strip()
    if not raw:
        raise ConfigError(
            "TG_ALLOWED_CHAT_IDS пуст. Бот в Telegram — публичная поверхность: "
            "без списка допущенных чатов доступ к риск-данным получает любой, "
            "кто узнал имя бота"
        )
    return frozenset(int(part) for part in raw.replace(" ", "").split(",") if part)


@dataclass(frozen=True)
class Settings:
    # Snowflake
    sf_account: str = field(default_factory=lambda: _required("SNOWFLAKE_ACCOUNT"))
    sf_user: str = field(default_factory=lambda: _required("SNOWFLAKE_USER"))
    sf_role: str = field(default_factory=lambda: os.environ.get("SNOWFLAKE_ROLE", "LLM_AGENT_RO"))
    # Отдельная роль для журнала: читатель писать не может ничем, писатель
    # риск-данных не видит. Совмещать в одну роль нельзя — см. snowflake_client.
    sf_writer_role: str = field(default_factory=lambda: os.environ.get("SNOWFLAKE_WRITER_ROLE", "COPILOT_WRITER"))
    sf_warehouse: str = field(default_factory=lambda: os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_COPILOT"))
    sf_private_key_path: str = field(default_factory=lambda: _required("SNOWFLAKE_PRIVATE_KEY_PATH"))
    sf_private_key_passphrase: str = field(
        default_factory=lambda: os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE", "")
    )

    # Объекты в аккаунте
    agent_name: str = field(default_factory=lambda: os.environ.get("COPILOT_AGENT", "RISK_GOV.AGENT.RISK_COPILOT"))

    # API
    api_key: str = field(default_factory=lambda: _required("COPILOT_API_KEY"))
    api_url: str = field(default_factory=lambda: os.environ.get("COPILOT_API_URL", "http://api:8770"))
    query_timeout_s: int = field(default_factory=lambda: _int("COPILOT_QUERY_TIMEOUT", 90))

    # Telegram
    tg_token: str = field(default_factory=lambda: _required("TG_BOT_TOKEN"))
    tg_allowed_chats: frozenset[int] = field(default_factory=_chat_allowlist)
    tg_alert_chat: int = field(default_factory=lambda: _int("TG_ALERT_CHAT_ID", 0))
    alert_poll_s: int = field(default_factory=lambda: _int("ALERT_POLL_SECONDS", 300))

    # Трейсинг — best-effort, без ключей выключается целиком
    langfuse_host: str = field(default_factory=lambda: os.environ.get("LANGFUSE_HOST", ""))
    langfuse_public_key: str = field(default_factory=lambda: os.environ.get("LANGFUSE_PUBLIC_KEY", ""))
    langfuse_secret_key: str = field(default_factory=lambda: os.environ.get("LANGFUSE_SECRET_KEY", ""))

    @property
    def tracing_enabled(self) -> bool:
        return bool(self.langfuse_host and self.langfuse_public_key and self.langfuse_secret_key)


_settings: Settings | None = None


def settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
