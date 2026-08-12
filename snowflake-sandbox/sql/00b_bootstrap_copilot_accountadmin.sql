---------------------------------------------------------------------------
-- Bootstrap для агента и стека на VPS.
--
-- ФАЙЛ РАЗДЕЛЁН НА ДВЕ ЧАСТИ, И ПОРЯДОК ВАЖЕН.
--
--   ЧАСТЬ A — под ACCOUNTADMIN. Всё, что требует прав на аккаунте:
--             параметры, интеграции, warehouse, пользователи, роли, политика сети.
--   ЧАСТЬ B — под HERMES_MCP_ROLE. Гранты на объекты RISK_GOV и git-репозиторий.
--
-- Почему нельзя одной ролью: после фазы 0 базами владеет HERMES_MCP_ROLE, и
-- вместе с владением у админа ушло право раздавать привилегии на их объекты.
-- `GRANT USAGE ON DATABASE RISK_GOV` под ACCOUNTADMIN упадёт. Это не
-- недосмотр, а следствие правила «у объекта один владелец» из фазы 0.
--
-- Запускать после фаз 12-13: часть B опирается на таблицы AGENT_RUN_LOG и
-- ALERT_LOG, созданные там.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
--                                                                        --
--                    ЧАСТЬ A — ПОД ACCOUNTADMIN                          --
--                                                                        --
---------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;


---------------------------------------------------------------------------
-- A1. ТРИ ПАРАМЕТРА CORTEX. Самостоятельная governance-находка.
--
-- Проверено 2026-08-12: все три стоят в положении по умолчанию, то есть
-- решение о них не принималось. Для мексиканского финтеха под CNBV это не
-- настройки производительности.
--
--   CORTEX_ENABLED_CROSS_REGION = ANY_REGION (дефолт DISABLED)
--       промпт с риск-данными может уехать на инференс в ЛЮБОЙ регион.
--       Это вопрос резидентности данных, а не latency.
--   CORTEX_MODELS_ALLOWLIST = ALL
--       какие модели допущены к риск-данным — не решено.
--   CORTEX_CODE_*_DAILY_EST_CREDIT_LIMIT_PER_USER = -1
--       подушный лимит расхода на AI есть нативно и снят.
--
-- Строки ниже закомментированы НАМЕРЕННО: каждое значение — решение владельца
-- данных, а не скрипта. Включать по одному, каждое — с записью в CHANGE_LOG.
--
-- ВНИМАНИЕ на первую строку: с DISABLED в регионе AWS_AP_SOUTH_1 часть моделей
-- (включая claude-4-sonnet) может стать недоступной — сейчас они отвечают
-- именно через cross-region. Проверять сразу после включения:
--   SELECT SNOWFLAKE.CORTEX.AI_COMPLETE('claude-4-sonnet', 'ping');
---------------------------------------------------------------------------

-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';
-- ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'claude-4-sonnet,llama3.1-8b';
-- ALTER ACCOUNT SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
-- ALTER ACCOUNT SET CORTEX_MCP_SERVER_FORCE_SQL_EXEC_READ_ONLY = TRUE;


---------------------------------------------------------------------------
-- A2. WAREHOUSE И БЮДЖЕТ АГЕНТА.
--
-- Отдельный warehouse нужен не для производительности, а чтобы вопрос
-- «сколько стоит агент» имел ответ, отделённый от стоимости пересборки
-- песочницы. Общий COMPUTE_WH такого ответа не даёт.
---------------------------------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS WH_COPILOT
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Вопросы к агенту. Отдельно от сборки, чтобы стоимость агента была видна отдельной строкой.';

CREATE RESOURCE MONITOR IF NOT EXISTS RM_COPILOT
    WITH CREDIT_QUOTA = 5
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS ON 80 PERCENT DO NOTIFY
             ON 100 PERCENT DO SUSPEND
             ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE WH_COPILOT SET RESOURCE_MONITOR = RM_COPILOT;


---------------------------------------------------------------------------
-- A3. СЕРВИСНЫЙ ПОЛЬЗОВАТЕЛЬ. Закрывает главный разрыв.
--
-- До этого шага у роли LLM_AGENT_RO ноль носителей: граница описана, но ни
-- разу не проверена в бою. Ключевая пара, а не пароль: пароль сервисного
-- пользователя рано или поздно оказывается в чьей-то истории команд.
--
-- Ключ генерируется на VPS и наружу не уезжает:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt
--   openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub
-- В RSA_PUBLIC_KEY идёт содержимое .pub БЕЗ строк BEGIN/END и без переводов строк.
---------------------------------------------------------------------------

CREATE USER IF NOT EXISTS PLATA_COPILOT_SVC
    TYPE = SERVICE
    DEFAULT_ROLE = LLM_AGENT_RO
    DEFAULT_WAREHOUSE = WH_COPILOT
    COMMENT = 'Сервисный пользователь стека agent-service на VPS.';

-- ALTER USER PLATA_COPILOT_SVC SET RSA_PUBLIC_KEY = '<одна строка из snowflake_key.pub>';

GRANT ROLE LLM_AGENT_RO TO USER PLATA_COPILOT_SVC;
GRANT USAGE, OPERATE ON WAREHOUSE WH_COPILOT TO ROLE LLM_AGENT_RO;


---------------------------------------------------------------------------
-- A4. ВТОРАЯ РОЛЬ: ЖУРНАЛЬНАЯ. Права на её объекты выдаются в части B.
--
-- Выяснилось на первом же INSERT из сервиса: под LLM_AGENT_RO записать журнал
-- прогонов нельзя — роль read-only, и вдобавок сессия ставит
-- CORTEX_CLIENT_READ_ONLY, который по описанию параметра нельзя выключить
-- обратно. Разводить пришлось не из-за механизма, а потому что это правильная
-- граница: личность, которая отвечает на вопросы, не может ничего записать;
-- личность, которая ведёт журнал, не видит риск-данных.
---------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS COPILOT_WRITER
    COMMENT = 'Только журнал: INSERT в AGENT_RUN_LOG, UPDATE отметок в ALERT_LOG. Риск-данных не видит.';

GRANT ROLE COPILOT_WRITER TO USER PLATA_COPILOT_SVC;
GRANT USAGE ON WAREHOUSE WH_COPILOT TO ROLE COPILOT_WRITER;


---------------------------------------------------------------------------
-- A5. GIT-ИНТЕГРАЦИЯ. Сам репозиторий создаётся в части B.
---------------------------------------------------------------------------

CREATE API INTEGRATION IF NOT EXISTS GH_TESTUDINATE
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Testudinate')
    ENABLED = TRUE
    COMMENT = 'Доступ к репозиториям Testudinate для GIT REPOSITORY.';

GRANT USAGE ON INTEGRATION GH_TESTUDINATE TO ROLE HERMES_MCP_ROLE;


---------------------------------------------------------------------------
-- A6. NETWORK POLICY. Ключ, утёкший из контейнера, вне IP VPS бесполезен.
--
-- Политика вешается на сервисного пользователя, а НЕ на аккаунт: аккаунтная
-- отрежет и вас самих из браузера.
---------------------------------------------------------------------------

-- CREATE NETWORK POLICY IF NOT EXISTS NP_COPILOT_VPS
--     ALLOWED_IP_LIST = ('<белый IP VPS>/32')
--     COMMENT = 'Только VPS, на котором крутится agent-service.';
-- ALTER USER PLATA_COPILOT_SVC SET NETWORK_POLICY = NP_COPILOT_VPS;


---------------------------------------------------------------------------
--                                                                        --
--                  ЧАСТЬ B — ПОД HERMES_MCP_ROLE                         --
--                                                                        --
-- Владелец RISK_GOV раздаёт права на свои объекты и создаёт git-репозиторий.
---------------------------------------------------------------------------

USE ROLE HERMES_MCP_ROLE;


---------------------------------------------------------------------------
-- B1. Права журнальной роли. Ровно два действия и ни одного объекта витрин.
---------------------------------------------------------------------------

GRANT USAGE ON DATABASE RISK_GOV                        TO ROLE COPILOT_WRITER;
GRANT USAGE ON SCHEMA RISK_GOV.AGENT                    TO ROLE COPILOT_WRITER;
GRANT USAGE ON SCHEMA RISK_GOV.DQ                       TO ROLE COPILOT_WRITER;
GRANT INSERT ON TABLE RISK_GOV.AGENT.AGENT_RUN_LOG      TO ROLE COPILOT_WRITER;
GRANT SELECT, UPDATE ON TABLE RISK_GOV.DQ.ALERT_LOG     TO ROLE COPILOT_WRITER;


---------------------------------------------------------------------------
-- B2. Права отвечающей роли на новые объекты фаз 11-13.
--
-- LLM_AGENT_RO получила права в фазе 8, когда Cortex Search, агента и
-- очереди алертов ещё не существовало. Без этих строк сервис на VPS
-- поднимется и упадёт на первом же вопросе.
--
-- УЖЕ ВЫПОЛНЕНО 2026-08-12 рабочей сессией — все шесть строк проходят.
-- Оставлены здесь ради воспроизводимости; повторный прогон безвреден.
---------------------------------------------------------------------------

GRANT USAGE ON CORTEX SEARCH SERVICE RISK_GOV.AGENT.CS_RISK_DOCS TO ROLE LLM_AGENT_RO;
GRANT USAGE ON AGENT RISK_GOV.AGENT.RISK_COPILOT                 TO ROLE LLM_AGENT_RO;
GRANT SELECT ON TABLE RISK_GOV.AGENT.DOC_CHUNKS                  TO ROLE LLM_AGENT_RO;
GRANT SELECT ON TABLE RISK_GOV.DQ.ALERT_LOG                      TO ROLE LLM_AGENT_RO;
GRANT SELECT ON VIEW RISK_GOV.DQ.V_COR_DRIFT                     TO ROLE LLM_AGENT_RO;
GRANT SELECT ON DYNAMIC TABLE RISK_GOV.DQ.DT_COR_MONTHLY         TO ROLE LLM_AGENT_RO;


---------------------------------------------------------------------------
-- B3. GIT-РЕПОЗИТОРИЙ. Пересборка песочницы из этого репозитория.
--
-- Самый короткий аргумент в разговоре о change management: изменение объекта
-- проходит через pull request, а не через окно Snowsight.
---------------------------------------------------------------------------

-- Приватный репозиторий требует секрета с токеном; публичный — нет.
-- CREATE SECRET RISK_GOV.META.GH_TOKEN
--     TYPE = password USERNAME = 'testudinate' PASSWORD = '<PAT с правом read на repo>';

CREATE OR REPLACE GIT REPOSITORY RISK_GOV.META.PLATA_REPO
    API_INTEGRATION = GH_TESTUDINATE
    ORIGIN = 'https://github.com/Testudinate/plata'
    -- GIT_CREDENTIALS = RISK_GOV.META.GH_TOKEN
    COMMENT = 'Исходники песочницы. Направление одно: репозиторий - источник, Snowflake - цель.';

ALTER GIT REPOSITORY RISK_GOV.META.PLATA_REPO FETCH;

-- Прогон файла фазы прямо из репозитория:
-- EXECUTE IMMEDIATE FROM @RISK_GOV.META.PLATA_REPO/branches/main/snowflake-sandbox/sql/13_alerts_and_dynamic.sql;
--
-- dbt-проект из репозитория вместо стейджа (тогда фаза 14 перестаёт быть
-- обходом через COPY INTO):
-- CREATE OR REPLACE DBT PROJECT RISK_GOV.META.PLATA_RISK_DBT
--     FROM @RISK_GOV.META.PLATA_REPO/branches/main/dbt;


---------------------------------------------------------------------------
-- ПРОВЕРКА ПОСЛЕ ПРОГОНА (под ACCOUNTADMIN):
--   SHOW ROLES LIKE 'LLM_AGENT_RO';     -- assigned_to_users должно стать 1
--   SHOW GRANTS TO ROLE COPILOT_WRITER; -- 7 строк, ни одной на витрины
--   SHOW WAREHOUSES LIKE 'WH_COPILOT';  -- resource_monitor = RM_COPILOT
--   SHOW GIT REPOSITORIES IN ACCOUNT;   -- 1
---------------------------------------------------------------------------
