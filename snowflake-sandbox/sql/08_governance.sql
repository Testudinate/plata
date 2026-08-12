---------------------------------------------------------------------------
-- Фаза 8. Governance-слой.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
--
-- Здесь заканчивается воспроизведение приложений и начинается собственно
-- ответ на задание. Пять блоков:
--   8.1 метаданные и каталог          (Part 1, Part 4)
--   8.2 канонический метрик-слой      (Part 2)
--   8.3 качество данных               (Part 2, Part 5)
--   8.4 управление изменениями        (Part 3)
--   8.5 доступ и PII                  (Part 1, Part 4)
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 8.1 МЕТАДАННЫЕ И КАТАЛОГ
--
-- Теги ставятся на СХЕМУ там, где свойство общее для всей схемы (слой, домен,
-- владелец): теги наследуются объектами, и 47 таблиц не нужно размечать
-- поштучно. Критичность, SLA, PII и знаковые соглашения — на конкретных
-- таблицах и колонках: у соседей контракты разные.
--
-- ВАЖНОЕ ОГРАНИЧЕНИЕ, найденное замером. Каталог НЕ строится на
-- SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES: эта вью отстаёт до двух часов,
-- сразу после разметки она пуста (проверено — вернула 0 строк). Каталог,
-- отстающий на два часа, не каталог. Поэтому теги остаются нативным
-- механизмом для линиджа и политик, а живой каталог читает
-- INFORMATION_SCHEMA плюс наши собственные реестры.
---------------------------------------------------------------------------

-- Разметка схем (сокращённо; полный список — в выполненных стейтментах).
ALTER SCHEMA RISK_DM.DM      SET TAG RISK_GOV.META.LAYER = 'dm',      RISK_GOV.META.DATA_DOMAIN = 'credit_risk', RISK_GOV.META.DATA_OWNER = 'Group IRM';
ALTER SCHEMA RISK_DM.TABLEAU SET TAG RISK_GOV.META.LAYER = 'tableau', RISK_GOV.META.DATA_DOMAIN = 'credit_risk', RISK_GOV.META.DATA_OWNER = 'Group IRM';
ALTER SCHEMA RISK_DM.DDS     SET TAG RISK_GOV.META.LAYER = 'dds',     RISK_GOV.META.DATA_DOMAIN = 'credit_risk', RISK_GOV.META.DATA_OWNER = 'Group IRM';
ALTER SCHEMA RISK_DM.RAW     SET TAG RISK_GOV.META.LAYER = 'raw',     RISK_GOV.META.DATA_DOMAIN = 'credit_risk', RISK_GOV.META.DATA_OWNER = 'Group IRM';
ALTER SCHEMA RISK_PROV.PROV  SET TAG RISK_GOV.META.LAYER = 'prov',    RISK_GOV.META.DATA_DOMAIN = 'provisions',  RISK_GOV.META.DATA_OWNER = 'Group IRM';
ALTER SCHEMA ODS.USER_MGMT   SET TAG RISK_GOV.META.LAYER = 'ods',     RISK_GOV.META.DATA_DOMAIN = 'customer',    RISK_GOV.META.DATA_OWNER = 'DWH Engineering';
-- ... остальные 17 схем размечены аналогично.

-- Критичность и SLA — на таблицах.
ALTER TABLE RISK_DM.DM.PORTFOLIO_COR       SET TAG RISK_GOV.META.CRITICALITY = 'tier1', RISK_GOV.META.REFRESH_SLA_HOURS = '48';
ALTER TABLE RISK_DM.DM.STM_COR_CC          SET TAG RISK_GOV.META.CRITICALITY = 'tier1', RISK_GOV.META.REFRESH_SLA_HOURS = '48';
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER SET TAG RISK_GOV.META.CRITICALITY = 'tier1', RISK_GOV.META.REFRESH_SLA_HOURS = '48';
ALTER TABLE RISK_PROV.PROV.MXGAAP_PROV_CC  SET TAG RISK_GOV.META.CRITICALITY = 'tier1', RISK_GOV.META.REFRESH_SLA_HOURS = '744';
ALTER TABLE ODS.REF.HOLIDAYS               SET TAG RISK_GOV.META.CRITICALITY = 'tier1', RISK_GOV.META.REFRESH_SLA_HOURS = '8760';

-- PII — на таблице и на каждой чувствительной колонке.
ALTER TABLE ODS.USER_MGMT.USER_DATA SET TAG RISK_GOV.META.CONTAINS_PII = 'yes';
ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN BIRTHDAY SET TAG RISK_GOV.META.CONTAINS_PII = 'yes';
ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN GENDER   SET TAG RISK_GOV.META.CONTAINS_PII = 'yes';
ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN STATE    SET TAG RISK_GOV.META.CONTAINS_PII = 'yes';

-- Знаковые соглашения — на КОЛОНКАХ: правило перестаёт быть строкой
-- в документе и становится свойством объекта.
ALTER TABLE RISK_DM.DM.STM_COR_CC MODIFY COLUMN COR_PRNP SET TAG RISK_GOV.META.SIGN_CONVENTION = 'negative_cost';
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER MODIFY COLUMN COR SET TAG RISK_GOV.META.SIGN_CONVENTION = 'negative_cost';
ALTER TABLE RISK_DM.DM.NPV_GEN5_DETAILS MODIFY COLUMN COR_TOTAL_PREDICT SET TAG RISK_GOV.META.SIGN_CONVENTION = 'positive_loss';
-- ... всего 10 колонок.

-- Устаревшее.
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER MODIFY COLUMN PRODUCT_RISKS SET TAG RISK_GOV.META.DEPRECATED_SINCE = '2025-11-01';
ALTER TABLE RISK_DM.DDS.STM_FACT_FORECAST SET TAG RISK_GOV.META.DEPRECATED_SINCE = '2026-05-01';


-- Реестр владения. Владение — не ярлык, а три РАЗДЕЛИМЫЕ обязанности:
-- владелец решает, что число означает; стюард получает алерт, когда качество
-- падает; технический владелец ведёт пайплайн. В большинстве организаций все
-- три неявно назначены тому, кто последним пожаловался.
CREATE OR REPLACE TABLE RISK_GOV.META.OWNERSHIP (
    OBJECT_NAME     COMMENT 'Fully qualified object',
    DATA_OWNER      COMMENT 'Unit accountable for the MEANING of the data: it decides what the numbers must be',
    DATA_STEWARD    COMMENT 'Named person accountable for OPERATIONAL quality: they get paged when a check fails',
    TECHNICAL_OWNER COMMENT 'Team that runs the pipeline producing the object',
    CRITICALITY     COMMENT 'tier1 feeds management reporting or regulatory output',
    SLA_HOURS       COMMENT 'Freshness threshold',
    SLA_CALENDAR    COMMENT 'business = measured in Mexican business days via ODS.REF.HOLIDAYS, calendar = wall clock. Getting this wrong turns every Monday into a false alarm',
    ON_BREACH       COMMENT 'What happens when the SLA is breached - ownership is only real if it names an action'
)
COMMENT = 'Who owns what, operationally.'
AS
          SELECT 'RISK_DM.DM.PORTFOLIO_COR'::TEXT, 'Group IRM'::TEXT, 'Datamart analyst 1'::TEXT, 'DWH Engineering'::TEXT, 'tier1'::TEXT, 48, 'calendar'::TEXT, 'page steward, notify Head of IRM if unresolved in 4h'::TEXT
UNION ALL SELECT 'RISK_DM.DM.PORTFOLIO_BS',        'Group IRM', 'Datamart analyst 1', 'DWH Engineering', 'tier1', 48,  'calendar', 'page steward, notify Head of IRM if unresolved in 4h'
UNION ALL SELECT 'RISK_DM.DM.STM_COR_CC',          'Group IRM', 'Datamart analyst 2', 'Group IRM',       'tier1', 48,  'business', 'page steward; Monday checks MUST use business days'
UNION ALL SELECT 'RISK_DM.DM.STM_CC',              'Group IRM', 'Datamart analyst 2', 'DWH Engineering', 'tier2', 120, 'business', 'ticket to DWH, no page - this table is known to lag'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER', 'Group IRM', 'Datamart analyst 1', 'Group IRM',       'tier1', 48,  'calendar', 'page steward, dashboards go stale immediately'
UNION ALL SELECT 'RISK_DM.DM.ACCOUNTS',            'Group IRM', 'Datamart analyst 1', 'DWH Engineering', 'tier1', 48,  'calendar', 'page steward, every DM join depends on it'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS',    'Risk Modelling', 'Model owner', 'Group IRM',         'tier2', 744, 'calendar', 'ticket to modelling team'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_AGG',        'Risk Modelling', 'Model owner', 'Group IRM',         'tier2', 744, 'calendar', 'ticket to modelling team'
UNION ALL SELECT 'RISK_PROV.PROV.MXGAAP_PROV_CC',  'Finance', 'Provisions lead', 'Group IRM',            'tier1', 744, 'business', 'escalate to CFO office - regulatory reporting input'
UNION ALL SELECT 'RISK_PROV.PROV.ADD_PROV',        'Finance', 'Provisions lead', 'Group IRM',            'tier2', 744, 'business', 'ticket to provisions team'
UNION ALL SELECT 'ODS.REF.HOLIDAYS',               'Group IRM', 'Datamart analyst 2', 'DWH Engineering', 'tier1', 8760, 'calendar', 'must be extended before year end or every SLA breaks silently'
UNION ALL SELECT 'ODS.PC_KERNEL.ACCOUNT',          'DWH Engineering', 'DWH on-call', 'DWH Engineering',  'tier1', 24, 'calendar', 'page DWH on-call'
UNION ALL SELECT 'ODS.USER_MGMT.USER_DATA',        'DWH Engineering', 'DWH on-call', 'DWH Engineering',  'tier2', 24, 'calendar', 'ticket to DWH. CONTAINS PII - access changes need DPO sign-off'
UNION ALL SELECT 'ODS.PF_ENGINE.STATEMENTS',       'DWH Engineering', 'DWH on-call', 'DWH Engineering',  'tier2', 24, 'calendar', 'ticket to DWH';


-- Реестр потребителей. Без него «оценить влияние изменения» = обзвонить всех,
-- а на практике — не обзвонить никого.
CREATE OR REPLACE TABLE RISK_GOV.META.CONSUMER_REGISTRY (
    OBJECT_NAME   COMMENT 'Fully qualified object being consumed',
    CONSUMER      COMMENT 'Name of the dashboard, report, model or agent',
    CONSUMER_TYPE COMMENT 'tableau | management_report | model | llm_agent | adhoc',
    CONTACT       COMMENT 'Who to warn',
    NOTICE_DAYS   COMMENT 'Days of notice this consumer needs before a breaking change',
    BREAKS_ON     COMMENT 'What kind of change actually breaks this consumer - not every change is breaking for everyone'
)
COMMENT = 'Who consumes each object. Turns "notify downstream consumers" from an intention into a query.'
AS
          SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS'::TEXT, 'CC statement-level COR vs forecast'::TEXT, 'tableau'::TEXT, 'BI team'::TEXT, 10, 'any change to COR_TOTAL_PREDICT values or grain'::TEXT
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS', 'Monthly management reporting (CUBE)', 'management_report', 'Head of IRM', 20, 'value changes on closed periods; new report_month is fine'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS', 'Risk analytics LLM agent', 'llm_agent', 'Group IRM', 0, 'column rename or drop; value changes need context-layer refresh, not notice'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_AGG',     'CLIP decisioning model', 'model', 'Risk Modelling', 30, 'EL LT shifts - the model is calibrated against it'
UNION ALL SELECT 'RISK_DM.DM.STM_COR_CC',       'CC statement-level COR vs forecast', 'tableau', 'BI team', 10, 'sign convention or grain change'
UNION ALL SELECT 'RISK_DM.DM.STM_COR_CC',       'Risk analytics LLM agent', 'llm_agent', 'Group IRM', 0, 'column rename or drop'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER', 'Collection effectiveness dashboard', 'tableau', 'Collections', 10, 'decomposition columns changing meaning'
UNION ALL SELECT 'RISK_DM.DM.PORTFOLIO_COR',    'Daily portfolio monitoring', 'tableau', 'BI team', 5, 'grain or filter column change'
UNION ALL SELECT 'RISK_DM.DM.PORTFOLIO_COR',    'Risk analytics LLM agent', 'llm_agent', 'Group IRM', 0, 'column rename or drop'
UNION ALL SELECT 'RISK_PROV.PROV.MXGAAP_PROV_CC', 'CNBV regulatory submission', 'management_report', 'Finance', 30, 'ANY change - regulatory output, needs re-certification';


-- Каталог. Живой, потому что читает INFORMATION_SCHEMA и наши реестры,
-- а не отстающую ACCOUNT_USAGE.TAG_REFERENCES.
-- Полный текст — в выполненном стейтменте; ключевое: одна строка на объект,
-- поля владения и SLA из OWNERSHIP, число потребителей из CONSUMER_REGISTRY,
-- признак DESCRIPTION_MISSING как измеримая метрика покрытия документацией.
--   Факт: 54 объекта, описания у 100%, владельцы у 14, потребители у 10.


---------------------------------------------------------------------------
-- 8.2 КАНОНИЧЕСКИЙ МЕТРИК-СЛОЙ (Part 2)
--
-- Три объекта: реестр определений, каноническая вью, мост.
--
-- КАНОН для COR: статементное зерно, Gen3 тотал, statement_num >= 2, x12,
-- знаменатель avg_balance_prnp_net. Обоснование — в поле RATIONALE реестра:
-- статементный цикл и есть событие, на котором метрика определена (резерв
-- двигается, когда пропущен платёж, а платежи привязаны к выписке).
-- Дневной снимок отвечает на другой вопрос — как сток двигался во вторник —
-- и подмешивает календарные эффекты в кредитную метрику.
--
-- Старые расчёты НЕ удаляются, а помечаются deprecated. Удаление никого не
-- мигрирует: оно лишь переносит прежний расчёт в Excel, где его не видно.
---------------------------------------------------------------------------

-- RISK_GOV.META.METRIC_DEFINITIONS — 4 записи: канонический COR_PCT_CC,
-- два deprecated-варианта (дневной Gen3 и дневной Gen2) и EL_LT_CC.
-- Каждая с зерном, числителем, знаменателем, обязательными фильтрами,
-- аннуализацией, владельцем и текстовым обоснованием.

CREATE OR REPLACE VIEW RISK_DM.DM.V_COR_CANONICAL
COMMENT = 'THE canonical Cost of Risk for credit cards. Definition COR_PCT_CC v1.0 in RISK_GOV.META.METRIC_DEFINITIONS. Statement grain, Gen3 total, statement_num >= 2, annualized * 12. Any dashboard, report or agent answering "what is our COR" must read this view and nothing else.'
AS
SELECT DATE_TRUNC('month', end_date) AS stmt_month, product_risks,
       COUNT(*) AS statements, COUNT(DISTINCT account_id) AS accounts,
       ROUND(-SUM(cor_prnp), 2) AS cor_mxn,
       ROUND(SUM(avg_balance_prnp_net), 2) AS avg_balance_mxn,
       ROUND(-SUM(cor_prnp) / NULLIF(SUM(avg_balance_prnp_net), 0) * 12 * 100, 4) AS cor_pct_annual,
       'COR_PCT_CC' AS metric_id, '1.0' AS metric_version
FROM RISK_DM.DM.STM_COR_CC
WHERE statement_num >= 2
GROUP BY 1, 2;


-- МОСТ. Каждый шаг меняет РОВНО ОДНО методическое решение и пересчитывается
-- из данных, поэтому остаток равен нулю по построению, а не подгонкой.
-- Это то, что прекращает спор: команды перестают сравнивать два числа
-- и начинают читать разложение разницы.
CREATE OR REPLACE VIEW RISK_GOV.DQ.V_COR_RECONCILIATION
COMMENT = 'The bridge from the canonical COR to each team number. Every step changes EXACTLY ONE methodological choice and is recomputed from the data, so the residual is zero by construction rather than by plugging.'
AS
WITH days AS (
    SELECT DATE_TRUNC('month', report_date) AS mth, COUNT(DISTINCT report_date) AS n_days
    FROM RISK_DM.DM.PORTFOLIO_COR GROUP BY 1
),
stm AS (
    SELECT DATE_TRUNC('month', end_date) AS mth,
           -SUM(IFF(statement_num >= 2, cor_prnp, 0))
             / NULLIF(SUM(IFF(statement_num >= 2, avg_balance_prnp_net, 0)), 0) * 12 * 100 AS v0_canonical,
           -SUM(cor_prnp) / NULLIF(SUM(avg_balance_prnp_net), 0) * 12 * 100 AS v1_all_statements
    FROM RISK_DM.DM.STM_COR_CC WHERE product_risks = 'CC' GROUP BY 1
),
daily AS (
    SELECT DATE_TRUNC('month', c.report_date) AS mth,
           SUM(c.cor + c.cor_0_bucket)  AS cor_gen3_total,
           SUM(c.cor)                   AS cor_gen3_excl_0bucket,
           SUM(c.cor_total)             AS cor_gen2_total,
           SUM(c.balance_net_prnp_gen3) AS bal_gen3,
           SUM(c.balance_net_prnp_gen2) AS bal_gen2
    FROM RISK_DM.RAW.SYNTH_PANEL_COR c WHERE c.product_risks = 'CC' GROUP BY 1
),
variants AS (
    SELECT s.mth, d.n_days, s.v0_canonical, s.v1_all_statements,
           -dl.cor_gen3_total        * d.n_days / NULLIF(dl.bal_gen3, 0) * 12 * 100 AS v2_daily_grain,
           -dl.cor_gen3_excl_0bucket * d.n_days / NULLIF(dl.bal_gen3, 0) * 12 * 100 AS v3_excl_0bucket,
           -dl.cor_gen3_excl_0bucket / NULLIF(dl.bal_gen3, 0) * 365 * 100           AS v4_annualized_365,
           -dl.cor_gen2_total        / NULLIF(dl.bal_gen2, 0) * 365 * 100           AS v5_gen2
    FROM stm s JOIN daily dl ON dl.mth = s.mth JOIN days d ON d.mth = s.mth
)
SELECT mth AS month_start,
       ROUND(v0_canonical, 2)                        AS canonical_pct,
       ROUND(v1_all_statements - v0_canonical, 2)    AS step1_drop_stmt2_filter_pp,
       ROUND(v2_daily_grain - v1_all_statements, 2)  AS step2_statement_to_daily_pp,
       ROUND(v3_excl_0bucket - v2_daily_grain, 2)    AS step3_exclude_0dpd_bucket_pp,
       ROUND(v4_annualized_365 - v3_excl_0bucket, 2) AS step4_x12_to_x365_pp,
       ROUND(v4_annualized_365, 2)                   AS portfolio_monitoring_pct,
       ROUND(v5_gen2 - v4_annualized_365, 2)         AS step5_gen3_to_gen2_pp,
       ROUND(v5_gen2, 2)                             AS finance_pct,
       ROUND(v0_canonical + (v1_all_statements - v0_canonical) + (v2_daily_grain - v1_all_statements)
           + (v3_excl_0bucket - v2_daily_grain) + (v4_annualized_365 - v3_excl_0bucket)
           + (v5_gen2 - v4_annualized_365) - v5_gen2, 6) AS residual_must_be_zero
FROM variants;

-- Апрель 2026: 14.62 -> -0.20 (снят фильтр) -> -2.14 (зерно) -> -0.53
-- (убран 0-бакет) -> +0.16 (аннуализация) = 11.92 Portfolio Monitoring
-- -> -0.54 (Gen3 -> Gen2) = 11.38 Finance. Остаток 0.
--
-- ВЫВОД, которого не было в исходной гипотезе: доминирует ЗЕРНО
-- (-2.14 п.п. в апреле, +2.72 в марте), а знаменитый фильтр
-- statement_num >= 2 даёт всего -0.05..-0.24 п.п. Самая известная «грабля»
-- из приложений оказалась третьестепенной. Проверять, а не доверять интуиции.


---------------------------------------------------------------------------
-- 8.3 КАЧЕСТВО ДАННЫХ (Part 2, Part 5)
--
-- Лестница DQM:
--   Basic -> Defined:    системные DMF Snowflake на критичных таблицах
--   Defined -> Controlled: СОБСТВЕННЫЕ DMF на семантику, а не на форму
--   Controlled -> ...:   светофор по 7 измерениям, владелец и действие
--
-- Расписание DMF СУТОЧНОЕ, не часовое: каждый прогон будит warehouse.
-- В бою частота выбирается по SLA таблицы, а не по умолчанию инструмента.
---------------------------------------------------------------------------

CREATE OR REPLACE DATA METRIC FUNCTION RISK_GOV.DQ.NON_BUSINESS_DAY_COUNT(ARG_T TABLE(DT DATE))
RETURNS NUMBER
COMMENT = 'Counts dates that fall on a Mexican weekend or public holiday. Attach to any weekday-only table: a nonzero result means the weekday-only contract of Appendix B is broken. Standard DMFs cannot express this - it needs the holiday calendar.'
AS
$$
SELECT COUNT(*) FROM ARG_T JOIN ODS.REF.HOLIDAYS h ON h."DATE" = ARG_T.DT
$$;

-- ДВЕ перегрузки: сигнатуры DMF типозависимы, и колонки витрин объявлены
-- как FLOAT. Первая попытка привязать NUMBER-версию к FLOAT-колонке упала
-- с «function does not exist» — именно поэтому системные DMF Snowflake
-- тоже поставляются перегрузками под каждый тип.
CREATE OR REPLACE DATA METRIC FUNCTION RISK_GOV.DQ.AGGREGATE_SIGN_VIOLATION(ARG_T TABLE(V FLOAT))
RETURNS NUMBER
COMMENT = 'Returns 1 when a cost column has a POSITIVE aggregate, i.e. the sign convention of Appendix C is inverted. Deliberately aggregate-level, not row-level: individual positive rows are legitimate provision releases when an account cures, and a row-level rule would fire on every healthy portfolio.'
AS
$$
SELECT IFF(COALESCE(SUM(V), 0) > 0, 1, 0) FROM ARG_T
$$;

ALTER TABLE RISK_DM.DM.PORTFOLIO_COR SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';
ALTER TABLE RISK_DM.DM.PORTFOLIO_COR ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();
ALTER TABLE RISK_DM.DM.PORTFOLIO_COR ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (ACCOUNT_ID);
ALTER TABLE RISK_DM.DM.PORTFOLIO_COR ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (PRODUCT_RISKS);
ALTER TABLE RISK_DM.DM.PORTFOLIO_COR ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (REPORT_DATE);

ALTER TABLE RISK_DM.DM.STM_COR_CC SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';
ALTER TABLE RISK_DM.DM.STM_COR_CC ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();
ALTER TABLE RISK_DM.DM.STM_COR_CC ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (END_DATE);
ALTER TABLE RISK_DM.DM.STM_COR_CC ADD DATA METRIC FUNCTION RISK_GOV.DQ.NON_BUSINESS_DAY_COUNT ON (END_DATE);
ALTER TABLE RISK_DM.DM.STM_COR_CC ADD DATA METRIC FUNCTION RISK_GOV.DQ.AGGREGATE_SIGN_VIOLATION ON (COR_PRNP);

ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (REPORT_DATE);
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER ADD DATA METRIC FUNCTION RISK_GOV.DQ.AGGREGATE_SIGN_VIOLATION ON (COR);
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (ACCOUNT_TYPE);

-- Плановый инцидент: STM_CC отстаёт по-настоящему, а не только в журнале ETL.
-- Изначально отставание было заложено только в метаданные, и скоркарта
-- показывала всё зелёным — то есть мониторинг измерял не то, что заявлял.
DELETE FROM RISK_DM.DM.STM_CC
WHERE end_date > (
    SELECT MIN(date_day) FROM (
        SELECT date_day FROM RISK_GOV.META.DIM_DATE
        WHERE is_business_day AND date_day <= (SELECT MAX(end_date) FROM RISK_DM.DM.STM_CC)
        ORDER BY date_day DESC LIMIT 8));

-- RISK_GOV.DQ.V_SCORECARD — светофор по 7 измерениям DMBoK: freshness,
-- completeness, accuracy, consistency, timeliness, validity, uniqueness.
-- Полный текст — в выполненном стейтменте.
--
-- КЛЮЧЕВОЕ В НЁМ: свежесть weekday-only таблиц измеряется в РАБОЧИХ днях
-- через ODS.REF.HOLIDAYS. Измерять их в календарных — значит каждую неделю
-- получать ложную тревогу в понедельник, а это способ, которым мониторинг
-- теряет аудиторию.
--
-- Факт: 22 проверки, 21 GREEN, 1 AMBER (STM_CC отстаёт на 9 рабочих дней
-- при SLA 5) — со стюардом и предписанным действием в той же строке.
--
-- Коррелированные подзапросы внутри вью Snowflake не поддерживает: первая
-- версия скоркарты упала с «Unsupported subquery type cannot be evaluated
-- inside VIEW object», расчёт отставания переписан через join.


---------------------------------------------------------------------------
-- 8.4 УПРАВЛЕНИЕ ИЗМЕНЕНИЯМИ (Part 3)
--
-- Пересчёт модели — это изменение ДАННЫХ без изменения СХЕМЫ: ничего
-- не ломается, ни один пайплайн не падает, и все дашборды тихо начинают
-- показывать другие числа. Реестр моделей — то, что вообще делает такое
-- изменение видимым.
---------------------------------------------------------------------------

-- RISK_GOV.META.MODEL_REGISTRY  — версии моделей, флаг RECALIBRATED,
--   затронутый скоуп и измеренный сдвиг EL LT (x1.35 для винтажей 2025 H1).
-- RISK_GOV.META.CHANGE_LOG      — журнал изменений. Самые опасные записи:
--   CHANGE_TYPE = semantics и IS_BREAKING = TRUE — ничего не падает,
--   запросы продолжают работать, а числа тихо значат другое.
-- RISK_GOV.META.V_CHANGE_IMPACT — оценка влияния как запрос, а не звонок:
--   кто потребляет объект, сколько дней уведомления ему нужно, что именно
--   для него ломается, и был ли процесс соблюдён (PROCESS_CHECK).

-- Версионированные вью: потребитель, которому нужна прежняя база расчёта,
-- закрепляется на снимке вместо спора о том, чьи цифры верны.
CREATE OR REPLACE VIEW RISK_DM.DM.V_NPV_GEN5_CURRENT
COMMENT = 'Gen5v1 as of the CURRENT model version (gen5v1_2026q2, the re-estimated one). Dedup by report_month is already applied.'
AS SELECT * FROM RISK_DM.DM.NPV_GEN5_DETAILS WHERE report_month = DATE '2026-06-01';

CREATE OR REPLACE VIEW RISK_DM.DM.V_NPV_GEN5_PREVIOUS
COMMENT = 'Gen5v1 as of the PREVIOUS model version (gen5v1_2026q1, before the re-estimation). Exists so a consumer who needs continuity can pin to the old basis for a stated period instead of arguing about which numbers are right. Retire it once the pinned consumers have migrated.'
AS SELECT * FROM RISK_DM.DM.NPV_GEN5_DETAILS WHERE report_month = DATE '2026-03-01';

-- Надгробие дропнутой таблицы. Запрос старых колонок падает с внятным
-- invalid identifier, а SELECT * показывает, куда идти. Это лучше, чем
-- «object does not exist»: сообщение объясняет само себя.
CREATE OR REPLACE VIEW RISK_DM.DM.NPV_GEN5_PV_DETAILS
COMMENT = 'TOMBSTONE. Dropped on 2026-05-01. Columns merged into RISK_DM.DM.NPV_GEN5_DETAILS. See RISK_GOV.META.CHANGE_LOG change_id = 2.'
AS SELECT 'DROPPED 2026-05-01 - use RISK_DM.DM.NPV_GEN5_DETAILS instead. See RISK_GOV.META.CHANGE_LOG change_id = 2.' AS DEPRECATION_NOTICE;


---------------------------------------------------------------------------
-- 8.5 ДОСТУП И PII (Part 1, Part 4)
--
-- Роль агента отграничена ПРАВАМИ, а не строчкой в промпте: LLM_AGENT_RO
-- не получает ни RAW, ни DDS, ни ODS вообще, поэтому до PII он не доходит
-- не потому, что ему не велели, а потому что не может.
-- Маскирование — вторая линия, не первая.
---------------------------------------------------------------------------

CREATE OR REPLACE MASKING POLICY RISK_GOV.META.PII_TEXT_MASK AS (VAL STRING) RETURNS STRING ->
    CASE WHEN CURRENT_ROLE() IN ('RISK_ANALYST_RW', 'ACCOUNTADMIN', 'HERMES_MCP_ROLE') THEN VAL
         ELSE '***MASKED***' END
    COMMENT = 'Text PII. Only the data-owning role sees raw values.';

CREATE OR REPLACE MASKING POLICY RISK_GOV.META.PII_DATE_MASK AS (VAL DATE) RETURNS DATE ->
    CASE WHEN CURRENT_ROLE() IN ('RISK_ANALYST_RW', 'ACCOUNTADMIN', 'HERMES_MCP_ROLE') THEN VAL
         ELSE DATE_TRUNC('year', VAL) END
    COMMENT = 'Date PII. Non-owning roles see the year only: age-band analysis stays possible, identification does not.';

ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN GENDER   SET MASKING POLICY RISK_GOV.META.PII_TEXT_MASK;
ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN STATE    SET MASKING POLICY RISK_GOV.META.PII_TEXT_MASK;
ALTER TABLE ODS.USER_MGMT.USER_DATA MODIFY COLUMN BIRTHDAY SET MASKING POLICY RISK_GOV.META.PII_DATE_MASK;

-- Гранты пяти ролям-персонам. Полный список — в выполненном стейтменте.
-- Существенное:
--   RISK_ANALYST_RO  — чтение RISK_DM, RISK_PROV, RISK_GOV, ODS (PII замаскирован)
--   FINANCE_RO       — только PROV и DM, без сырых слоёв
--   TABLEAU_SVC_RO   — только схема RISK_DM.TABLEAU
--   LLM_AGENT_RO     — DM, TABLEAU и RISK_GOV.{AGENT,META,DQ}. НЕ выдаётся
--                      RAW, DDS и ODS целиком


---------------------------------------------------------------------------
-- ПРИЁМКА ФАЗЫ 8:
--   каталог                54 объекта, описания 100%, владельцы у 14
--   мост между расчётами   остаток 0 во всех месяцах
--   скоркарта              22 проверки, 21 GREEN, 1 AMBER с владельцем и действием
--   DMF                    12 привязок на 3 критичных таблицах, суточное расписание
--   реестр изменений       4 записи, из них 3 ломающих
--   маскирование           3 колонки PII, две политики
---------------------------------------------------------------------------
