---------------------------------------------------------------------------
-- Фаза 3. Слой ODS: структуры.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
-- Под ACCOUNTADMIN упадёт — см. шапку 01_schemas_and_tags.sql.
--
-- ПОРЯДОК. Здесь только СТРУКТУРЫ. Наполнение ACCOUNT, USER_DATA и STATEMENTS
-- перенесено в фазу 4: строки этих таблиц должны происходить из той же
-- сгенерированной вселенной счетов, что и витрины DM. Иначе ODS и DM разойдутся
-- между собой, и джойны из Appendix F перестанут сходиться — то есть сломается
-- ровно то, ради чего песочница и строится.
--
-- USDMXN наполняется сразу: курс от счетов не зависит.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 3.1 ODS.PC_KERNEL.ACCOUNT — мастер счетов.
--
-- Ключ намеренно назван ID, а не ACCOUNT_ID: Appendix F прямо предупреждает,
-- что часть ODS-таблиц зовёт ту же сущность иначе. Воспроизводим ловушку,
-- а не «исправляем» её.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE ODS.PC_KERNEL."ACCOUNT" (
    ID                 TEXT          COMMENT 'Account UUID. NOTE: this ODS table names the key ID, while every DM table calls the same entity ACCOUNT_ID (Appendix F gotcha)',
    CLIENT_ID          TEXT          COMMENT 'Client UUID. One client can hold several accounts (CC + PL + GRZD)',
    ACCOUNT_TYPE       TEXT          COMMENT 'Product code: CC, GRZD, GRZD_CLIPPED, PL, POS. Same values as PRODUCT_RISKS in DM, different column name',
    ACCOUNT_STATE      TEXT          COMMENT 'ACTIVE / BLOCKED / CLOSED / WRITTEN_OFF',
    OPEN_DTTM          TIMESTAMP_NTZ COMMENT 'Account opening timestamp in UTC. DM tables carry Mexico City dates - naive casting to DATE shifts the day (Appendix F)',
    CREDIT_LIMIT       NUMBER(18,2)  COMMENT 'Current credit limit, MXN',
    "__PROCESSED_DTTM" TIMESTAMP_NTZ COMMENT 'ETL processing timestamp'
)
COMMENT = 'Account master, the source of account_id / client_id / account_state / account_type for the whole warehouse. Grain: one row per account. Appendix A, F.';


---------------------------------------------------------------------------
-- 3.2 ODS.USER_MGMT.USER_DATA — демография клиента. PII.
-- На этой таблице в фазе 8 демонстрируется маскирование и граница доступа
-- роли LLM_AGENT_RO.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE ODS.USER_MGMT.USER_DATA (
    CLIENT_ID          TEXT          COMMENT 'Client UUID. Join key from DM.ACCOUNTS.CLIENT_ID (Appendix F)',
    GENDER             TEXT          COMMENT 'M / F. PII',
    BIRTHDAY           DATE          COMMENT 'Date of birth. PII - masked for every role except RISK_ANALYST_RW',
    STATE              TEXT          COMMENT 'Mexican state of residence. PII (quasi-identifier)',
    "__PROCESSED_DTTM" TIMESTAMP_NTZ COMMENT 'ETL processing timestamp'
)
COMMENT = 'Client demographics used to enrich DM tables through CLIENT_ID. CONTAINS PII: masking policies apply, role LLM_AGENT_RO is never granted access. Appendix A, F.';


---------------------------------------------------------------------------
-- 3.3 ODS.PF_ENGINE.STATEMENTS — сырые статементы.
--
-- STATEMENT_ID — INTEGER, а не UUID (Appendix F). Таймстемпы в UTC, тогда как
-- DM хранит то же событие датой Mexico City в END_DATE: наивный джойн по
-- STATEMENT_DTTM::DATE = END_DATE будет терять строки. Так и задумано.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE ODS.PF_ENGINE.STATEMENTS (
    STATEMENT_ID       NUMBER(38,0)  COMMENT 'CC billing statement identifier. INTEGER, not UUID - unlike account_id (Appendix F)',
    ACCOUNT_ID         TEXT          COMMENT 'Account UUID',
    STATEMENT_NUM      NUMBER(38,0)  COMMENT 'Sequential statement number per account, starting at 1',
    STATEMENT_DTTM     TIMESTAMP_NTZ COMMENT 'Statement cut timestamp in UTC. DM carries the same event as a Mexico City DATE in END_DATE - the two differ by the UTC offset (Appendix F)',
    DUE_DTTM           TIMESTAMP_NTZ COMMENT 'Payment due timestamp in UTC',
    CLOSING_BALANCE    NUMBER(18,2)  COMMENT 'Statement closing balance, MXN',
    MIN_PAYMENT        NUMBER(18,2)  COMMENT 'Minimum payment due, MXN',
    "__PROCESSED_DTTM" TIMESTAMP_NTZ COMMENT 'ETL processing timestamp'
)
COMMENT = 'Raw CC billing statements. Grain: account x statement_num. Source of STATEMENT_ID for DM.STM_CC enrichment. Timestamps are UTC while DM is Mexico City - the timezone trap from Appendix F lives here. Appendix A, F.';


---------------------------------------------------------------------------
-- 3.4 ODS.FX_RATES.USDMXN — курс. Единственная ODS-таблица, наполняемая сразу.
-- Детерминированная прогулка вокруг 18 MXN/USD: две гармоники плюс дрожание
-- от HASH(дата). RANDOM() не используется нигде в песочнице — пересборка
-- обязана давать те же данные, иначе цифры в отчёте разъедутся с базой.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE ODS.FX_RATES.USDMXN (
    RATE_DATE          COMMENT 'Quotation date',
    RATE               COMMENT 'USD/MXN closing rate published by Banxico',
    SOURCE             COMMENT 'Publishing source',
    "__PROCESSED_DTTM" COMMENT 'ETL processing timestamp'
)
COMMENT = 'USD/MXN exchange rate history. Synthetic: a deterministic walk around 18 MXN/USD, not real Banxico quotes. Appendix A.'
AS
SELECT d.date_day,
       ROUND(18.0
             + 1.6 * SIN(DATEDIFF('day', DATE '2024-01-01', d.date_day) / 58.0)
             + 0.9 * COS(DATEDIFF('day', DATE '2024-01-01', d.date_day) / 23.0)
             + (MOD(ABS(HASH(d.date_day, 'fx')), 41) - 20) / 400.0, 4)::NUMBER(12,4),
       'BANXICO'::TEXT,
       '2026-08-01 04:00:00'::TIMESTAMP_NTZ
FROM RISK_GOV.META.DIM_DATE d
WHERE d.is_business_day;

-- Факт: 1005 строк, 2024-01-02 .. 2027-12-31, курс в коридоре 15.47 .. 20.45.


---------------------------------------------------------------------------
-- ОСТАЛОСЬ В ФАЗЕ 3 (скелеты P2, создаются вместе с фазой 6):
--   ODS.PC_TARIFFS.TARIFFS_ACCOUNTS
--   ODS.PC_APP.TRANSACTIONS (включая тип SPEI_IN)
--   ODS.PF_LOANS.TRANCHES
--   ODS.PF_GL.GL_ENTRY_SOURCES, ODS.PF_GL.GL_SOURCE_ENGINE
-- Они нужны только для полноты карты схем и от вселенной счетов не зависят.
---------------------------------------------------------------------------
