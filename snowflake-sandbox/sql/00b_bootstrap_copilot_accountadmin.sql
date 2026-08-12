---------------------------------------------------------------------------
-- Bootstrap для агента и стека на VPS. ВТОРОЙ и последний файл, который
-- запускается вручную под ACCOUNTADMIN.
--
-- Всё, что здесь есть, требует прав на аккаунте и поэтому недоступно рабочей
-- сессии под HERMES_MCP_ROLE: пользователи, интеграции, параметры аккаунта,
-- resource monitor, network policy.
--
-- Порядок: сначала 00_bootstrap_accountadmin.sql, потом фазы 1-14 рабочей
-- ролью, потом этот файл — он опирается на объекты фаз 12-13.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 1. ТРИ ПАРАМЕТРА CORTEX. Самостоятельная governance-находка.
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
-- Ниже — осознанные значения, а не «как было». Каждое требует решения
-- владельца данных, поэтому строки закомментированы намеренно: их включает
-- человек, а не скрипт.
---------------------------------------------------------------------------

-- Инференс не покидает регион аккаунта:
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';
-- Либо явный список регионов, если модель нужного класса локально недоступна:
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

-- Только модели, прошедшие ревью:
-- ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'claude-4-sonnet,llama3.1-8b';

-- Подушный дневной лимит расхода:
-- ALTER ACCOUNT SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;

-- Аккаунт-уровневый запрет записи для MCP-сервера. Поверх прав роли, и в
-- отличие от них не зависит от ошибки в грантах:
-- ALTER ACCOUNT SET CORTEX_MCP_SERVER_FORCE_SQL_EXEC_READ_ONLY = TRUE;

-- Каждое включение — запись в журнал изменений, иначе V_SCHEMA_DRIFT права:
-- INSERT INTO RISK_GOV.META.CHANGE_LOG ... (см. 08_governance.sql)


---------------------------------------------------------------------------
-- 2. GIT-РЕПОЗИТОРИЙ. Пересборка песочницы из этого репозитория.
--
-- Самый короткий аргумент в разговоре о change management: изменение объекта
-- проходит через pull request, а не через окно Snowsight.
---------------------------------------------------------------------------

CREATE API INTEGRATION IF NOT EXISTS GH_TESTUDINATE
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Testudinate')
    ENABLED = TRUE
    COMMENT = 'Доступ к репозиториям Testudinate для GIT REPOSITORY.';

GRANT USAGE ON INTEGRATION GH_TESTUDINATE TO ROLE HERMES_MCP_ROLE;

-- Приватный репозиторий требует секрета с токеном; публичный — нет.
-- CREATE SECRET RISK_GOV.META.GH_TOKEN
--     TYPE = password USERNAME = 'testudinate' PASSWORD = '<PAT>';

CREATE OR REPLACE GIT REPOSITORY RISK_GOV.META.PLATA_REPO
    API_INTEGRATION = GH_TESTUDINATE
    ORIGIN = 'https://github.com/Testudinate/plata'
    -- GIT_CREDENTIALS = RISK_GOV.META.GH_TOKEN
    COMMENT = 'Исходники песочницы. Направление одно: репозиторий - источник, Snowflake - цель.';

-- ALTER GIT REPOSITORY RISK_GOV.META.PLATA_REPO FETCH;
-- EXECUTE IMMEDIATE FROM @RISK_GOV.META.PLATA_REPO/branches/main/snowflake-sandbox/sql/11_cortex_search.sql;
--
-- dbt-проект из репозитория вместо стейджа (тогда фаза 14 перестаёт быть
-- обходом через COPY INTO):
-- CREATE OR REPLACE DBT PROJECT RISK_GOV.META.PLATA_RISK_DBT
--     FROM @RISK_GOV.META.PLATA_REPO/branches/main/dbt;


---------------------------------------------------------------------------
-- 3. WAREHOUSE И БЮДЖЕТ АГЕНТА.
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
-- 4. СЕРВИСНЫЙ ПОЛЬЗОВАТЕЛЬ. Закрывает главный разрыв.
--
-- До этого шага у роли LLM_AGENT_RO ноль носителей: граница описана, но ни
-- разу не проверена в бою. Ключевая пара, а не пароль: пароль сервисного
-- пользователя рано или поздно оказывается в чьей-то истории команд.
--
-- Ключ генерируется на VPS и наружу не уезжает:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt
--   openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub
---------------------------------------------------------------------------

CREATE USER IF NOT EXISTS PLATA_COPILOT_SVC
    TYPE = SERVICE
    DEFAULT_ROLE = LLM_AGENT_RO
    DEFAULT_WAREHOUSE = WH_COPILOT
    COMMENT = 'Сервисный пользователь стека agent-service на VPS.';

-- ALTER USER PLATA_COPILOT_SVC SET RSA_PUBLIC_KEY = '<содержимое snowflake_key.pub без заголовков>';

GRANT ROLE LLM_AGENT_RO TO USER PLATA_COPILOT_SVC;
GRANT USAGE, OPERATE ON WAREHOUSE WH_COPILOT TO ROLE LLM_AGENT_RO;


---------------------------------------------------------------------------
-- 5. ВТОРАЯ РОЛЬ: ЖУРНАЛЬНАЯ.
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

GRANT USAGE ON DATABASE RISK_GOV TO ROLE COPILOT_WRITER;
GRANT USAGE ON SCHEMA RISK_GOV.AGENT TO ROLE COPILOT_WRITER;
GRANT USAGE ON SCHEMA RISK_GOV.DQ TO ROLE COPILOT_WRITER;
GRANT INSERT ON TABLE RISK_GOV.AGENT.AGENT_RUN_LOG TO ROLE COPILOT_WRITER;
GRANT SELECT, UPDATE ON TABLE RISK_GOV.DQ.ALERT_LOG TO ROLE COPILOT_WRITER;
GRANT USAGE ON WAREHOUSE WH_COPILOT TO ROLE COPILOT_WRITER;
GRANT ROLE COPILOT_WRITER TO USER PLATA_COPILOT_SVC;

-- Явный запрет на всё остальное — по умолчанию роль и так ничего не видит,
-- но проверка обязана быть воспроизводимой:
-- SHOW GRANTS TO ROLE COPILOT_WRITER;   -- ожидается ровно 7 строк выше


---------------------------------------------------------------------------
-- 6. NETWORK POLICY. Ключ, утёкший из контейнера, вне IP VPS бесполезен.
---------------------------------------------------------------------------

-- CREATE NETWORK POLICY IF NOT EXISTS NP_COPILOT_VPS
--     ALLOWED_IP_LIST = ('<белый IP VPS>/32')
--     COMMENT = 'Только VPS, на котором крутится agent-service.';
-- ALTER USER PLATA_COPILOT_SVC SET NETWORK_POLICY = NP_COPILOT_VPS;


---------------------------------------------------------------------------
-- 7. АГЕНТ В SNOWFLAKE INTELLIGENCE (необязательно).
--
-- Агент из фазы 12 живёт в RISK_GOV.AGENT и вызывается через
-- DATA_AGENT_RUN. Чтобы он появился в UI Snowflake Intelligence, копия
-- создаётся в стандартной базе:
-- CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
-- CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;
-- GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE HERMES_MCP_ROLE;
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- ПРОВЕРКА ПОСЛЕ ПРОГОНА:
--   SHOW ROLES LIKE 'LLM_AGENT_RO';        -- assigned_to_users должно стать 1
--   SHOW GRANTS TO ROLE COPILOT_WRITER;    -- 7 строк, ни одной на витрины
--   SHOW WAREHOUSES LIKE 'WH_COPILOT';     -- resource_monitor = RM_COPILOT
--   SHOW GIT REPOSITORIES IN ACCOUNT;      -- 1
---------------------------------------------------------------------------
