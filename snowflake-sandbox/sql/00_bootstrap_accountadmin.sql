---------------------------------------------------------------------------
-- Фаза 0. Одноразовый bootstrap. Запускать ВРУЧНУЮ в Snowsight под ACCOUNTADMIN.
--
-- Зачем вручную: сессия MCP закреплена за ролью HERMES_MCP_ROLE, USE ROLE в ней
-- запрещено, а CREATE DATABASE / CREATE ROLE / гранты на аккаунте требуют
-- ACCOUNTADMIN. Всё остальное после этого скрипта делается уже из сессии.
--
-- Идемпотентен: повторный запуск безопасен.
-- Откат — в самом низу файла.
---------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

---------------------------------------------------------------------------
-- 1. Базы данных. Имена — ровно как в Appendix A, плюс RISK_GOV (наш слой).
---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS ODS             COMMENT = 'Operational Data Store (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS RISK_DM         COMMENT = 'Risk Data Mart: dm / tableau / dds / raw (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS RISK_PROV       COMMENT = 'Risk Reserves, MxGAAP provisions (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS RISK_LEGACY     COMMENT = 'Legacy risk DM: PD model outputs (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS RISK_RDS        COMMENT = 'Risk RDS detail store (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS CREDIT_PROD     COMMENT = 'Credit product dbt layer (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS COLLECTION_PROD COMMENT = 'Collection dbt layer (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS PAYMENTS_PROD   COMMENT = 'Payment processing dbt layer (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS POS_PROD        COMMENT = 'POS detail store (sandbox, synthetic)';
CREATE DATABASE IF NOT EXISTS RISK_GOV        COMMENT = 'Governance layer: catalog, DQ, LLM context. Not in appendices.';

---------------------------------------------------------------------------
-- 2. Владение базами отдаём рабочей роли.
--    Отдаём владение конкретными базами, а НЕ CREATE DATABASE ON ACCOUNT:
--    грант уже, отзывается одной строкой, власти над аккаунтом роль не получает.
---------------------------------------------------------------------------

GRANT OWNERSHIP ON DATABASE ODS             TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RISK_DM         TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RISK_PROV       TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RISK_LEGACY     TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RISK_RDS        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE CREDIT_PROD     TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE COLLECTION_PROD TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE PAYMENTS_PROD   TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE POS_PROD        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RISK_GOV        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;

-- Владение схемами PUBLIC внутри них — тем же владельцем, иначе схема останется
-- за ACCOUNTADMIN и в неё нельзя будет писать из сессии.
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE ODS             TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE RISK_DM         TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE RISK_PROV       TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE RISK_LEGACY     TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE RISK_RDS        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE CREDIT_PROD     TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE COLLECTION_PROD TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE PAYMENTS_PROD   TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE POS_PROD        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE RISK_GOV        TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;

---------------------------------------------------------------------------
-- 3. Роли-персоны. Нужны для Part 1 («кто чем владеет») и Part 4 («доступ агента»).
--    Права на объекты им выдаст уже рабочая роль — она будет их владельцем.
--    Роль агента отдельная от человеческой сознательно: у агента другой профиль
--    риска, и ограничивать его надо правами, а не строчкой в промпте.
---------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS RISK_ANALYST_RW COMMENT = 'Аналитик риска: владелец слоя dm, чтение всего';
CREATE ROLE IF NOT EXISTS RISK_ANALYST_RO COMMENT = 'Аналитик риска: только чтение';
CREATE ROLE IF NOT EXISTS FINANCE_RO      COMMENT = 'Финансы: чтение витрин и провизий';
CREATE ROLE IF NOT EXISTS TABLEAU_SVC_RO  COMMENT = 'Сервисная учётка Tableau: чтение схемы tableau';
CREATE ROLE IF NOT EXISTS LLM_AGENT_RO    COMMENT = 'LLM-агент: чтение витрин и risk_gov.agent. Без raw, dds и PII';

GRANT OWNERSHIP ON ROLE RISK_ANALYST_RW TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE RISK_ANALYST_RO TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE FINANCE_RO      TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE TABLEAU_SVC_RO  TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ROLE LLM_AGENT_RO    TO ROLE HERMES_MCP_ROLE COPY CURRENT GRANTS;

-- Warehouse принадлежит ACCOUNTADMIN, поэтому доступ к нему раздаём здесь.
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE RISK_ANALYST_RW;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE RISK_ANALYST_RO;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE FINANCE_RO;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TABLEAU_SVC_RO;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE LLM_AGENT_RO;

---------------------------------------------------------------------------
-- 4. Привилегии на аккаунте, нужные для Фаз 8–9 (Data Quality, алерты).
--    Без них DMF нельзя навесить на таблицу и нельзя прочитать их результаты.
---------------------------------------------------------------------------

GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE HERMES_MCP_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE HERMES_MCP_ROLE;

-- Понадобятся в Фазе 8.3 (регулярный пересчёт DQ) и 8.4 (алерты о нарушении SLA).
-- Выдаём сразу, чтобы не возвращаться к ACCOUNTADMIN второй раз.
GRANT EXECUTE TASK  ON ACCOUNT TO ROLE HERMES_MCP_ROLE;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE HERMES_MCP_ROLE;

---------------------------------------------------------------------------
-- 5. Ограничитель расходов. Песочница синтетическая, но warehouse настоящий.
---------------------------------------------------------------------------

ALTER WAREHOUSE COMPUTE_WH SET
    WAREHOUSE_SIZE   = 'XSMALL'
    AUTO_SUSPEND     = 60
    AUTO_RESUME      = TRUE
    INITIALLY_SUSPENDED = FALSE;

CREATE RESOURCE MONITOR IF NOT EXISTS RM_SANDBOX
    WITH CREDIT_QUOTA = 20
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75  PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = RM_SANDBOX;

---------------------------------------------------------------------------
-- 6. Проверка: должно вернуться 10 строк, все — с owner = HERMES_MCP_ROLE.
---------------------------------------------------------------------------

SHOW DATABASES LIKE '%';

---------------------------------------------------------------------------
-- ОТКАТ (если песочница больше не нужна)
---------------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
-- DROP DATABASE IF EXISTS ODS;
-- DROP DATABASE IF EXISTS RISK_DM;
-- DROP DATABASE IF EXISTS RISK_PROV;
-- DROP DATABASE IF EXISTS RISK_LEGACY;
-- DROP DATABASE IF EXISTS RISK_RDS;
-- DROP DATABASE IF EXISTS CREDIT_PROD;
-- DROP DATABASE IF EXISTS COLLECTION_PROD;
-- DROP DATABASE IF EXISTS PAYMENTS_PROD;
-- DROP DATABASE IF EXISTS POS_PROD;
-- DROP DATABASE IF EXISTS RISK_GOV;
-- DROP ROLE IF EXISTS RISK_ANALYST_RW;
-- DROP ROLE IF EXISTS RISK_ANALYST_RO;
-- DROP ROLE IF EXISTS FINANCE_RO;
-- DROP ROLE IF EXISTS TABLEAU_SVC_RO;
-- DROP ROLE IF EXISTS LLM_AGENT_RO;
-- REVOKE EXECUTE DATA METRIC FUNCTION ON ACCOUNT FROM ROLE HERMES_MCP_ROLE;
-- REVOKE EXECUTE TASK  ON ACCOUNT FROM ROLE HERMES_MCP_ROLE;
-- REVOKE EXECUTE ALERT ON ACCOUNT FROM ROLE HERMES_MCP_ROLE;
-- REVOKE DATABASE ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER FROM ROLE HERMES_MCP_ROLE;
-- ALTER WAREHOUSE COMPUTE_WH UNSET RESOURCE_MONITOR;
-- DROP RESOURCE MONITOR IF EXISTS RM_SANDBOX;
