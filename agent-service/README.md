# agent-service — доступ к риск-агенту из Telegram

Тонкий стек на VPS поверх агента, который живёт **внутри** Snowflake
(`RISK_GOV.AGENT.RISK_COPILOT`). Здесь нет ни промптов, ни формул, ни порогов:
всё это в аккаунте, рядом с данными. Наружу вынесено ровно то, чего в
Snowflake нет.

## Что здесь и почему именно это

| Компонент | Зачем снаружи |
|-----------|---------------|
| `bot.py` — Telegram, allowlist по `chat_id` | шлюза в мессенджер у Snowflake нет |
| `api.py` — FastAPI между ботом и Snowflake | одна точка, где ставится `QUERY_TAG`, режется таймаут и пишется трейс; вторая поверхность (MCP, веб) подключается к ней же |
| доставка алертов | `NOTIFICATION INTEGRATION` в Telegram потребовала бы `ACCOUNTADMIN` и хранения токена бота внутри аккаунта. Snowflake кладёт условие в `RISK_GOV.DQ.ALERT_LOG`, бот забирает и отмечает доставку |
| `eval_agent.py` — ночной регресс | оценка агента инструментом того же вендора, которым агент сделан, слабее как свидетельство. Набор и вердикт держим у себя |
| учёт стоимости | кредиты Snowflake и токены модели сводятся в один отчёт вместе с остальными проектами (`hermes-memory/src/pricing.py`) |

Чего здесь **нет** и не будет: своей формулы COR (она в `METRIC_CONTRACTS` и
в `SV_COR`), своего векторного индекса (он в `CS_RISK_DOCS`), своего права
писать в базу (роль `LLM_AGENT_RO`), своего веб-UI.

## Как это работает

```
Telegram (allowlist)                 cron в контейнере
      │ /ask ...                            │ каждые 5 минут
      ▼                                     ▼
 bot.py ──► api.py :8770 ──► Snowflake: DATA_AGENT_RUN(RISK_COPILOT)
                  │                        ├─ cor_metrics  → SEMANTIC_VIEW(SV_COR)
                  │                        ├─ risk_docs    → CORTEX SEARCH CS_RISK_DOCS
                  │                        └─ sql_exec     → SELECT под LLM_AGENT_RO
                  │
                  ├──► pitfall_check: DETECTION_SQL из AGENT.PITFALLS по выданному SQL
                  ├──► AGENT.AGENT_RUN_LOG: вопрос, ответ, инструменты, стоимость
                  └──► DQ.ALERT_LOG: недоставленные условия → в чат, отметка доставки
```

## Запуск

```bash
cp .env.example .env          # заполнить, без значений сервис не стартует
docker network create llm-shared 2>/dev/null || true
docker compose up -d --build
curl -s http://127.0.0.1:8770/healthz
```

Ключ Snowflake монтируется файлом только на чтение и в образ не копируется.
Порт 8770 привязан к `127.0.0.1` — наружу не публикуется никогда; бот ходит к
API по внутренней сети compose, а с Telegram говорит исходящими запросами
(long polling), поэтому входящий порт наружу не нужен вовсе.

## Что надо сделать в Snowflake один раз

`../snowflake-sandbox/sql/00_bootstrap_accountadmin.sql`, блок 6 — сервисный
пользователь `PLATA_COPILOT_SVC` с key-pair, ролью `LLM_AGENT_RO`, network
policy на IP этого VPS и собственным warehouse `WH_COPILOT` с отдельным
resource monitor. Пока пользователя нет, у роли ноль носителей: граница
описана, но не проверена.

## Проверки

Прогон идёт 5–8 минут: 16 вопросов последовательно, каждый по 10–30 секунд.
Это ночная проверка, а не интерактивная — в терминале её легко прервать на
середине, поэтому лучше в фоне с логом.

```bash
mkdir -p data && chown 10001:10001 data          # один раз

# снять базу (в фоне, лог рядом)
docker compose exec -T api python -m app.eval_agent --save /srv/data/baseline.json \
  > data/eval.log 2>&1 &

# сравнить после изменения контекста, промпта или модели
docker compose exec -T api python -m app.eval_agent --compare /srv/data/baseline.json
```

`data/` смонтирован в контейнер, поэтому baseline переживает `up -d --build`.
Без этого после первой же пересборки сравнивать не с чем.

Прогон валится с кодом 2 при деградации против baseline. Метрики: доля
числовых ответов в пределах `TOLERANCE`, доля правильно выбранного объекта,
срабатывания `DETECTION_SQL` (целевое — ноль), корректность отказов,
p95 латентности и стоимость вопроса. Разбивка по `DIFFICULTY` обязательна:
общая точность упирается в потолок на лёгких вопросах и прячет провал на hard.
