---------------------------------------------------------------------------
-- Фаза 2. Референсный слой и календарь.
--
-- Первым делом, потому что от календаря зависят и статементы (weekday-only
-- end_date), и SLA-мониторинг, и пересчёт COR в годовые (run rate).
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
-- Под ACCOUNTADMIN упадёт — см. шапку 01_schemas_and_tags.sql.
--
-- Пять стейтментов, запускать по одному.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 2.1 ODS.REF.HOLIDAYS — состав колонок дословно по Appendix B.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE ODS.REF.HOLIDAYS (
    "KEY"                  VARIANT       COMMENT 'JSON with internal date serial - ignore, use DATE',
    "DATE"                 DATE          COMMENT 'Calendar date of the non-business day',
    "TYPE"                 TEXT          COMMENT 'WEEKEND (Sat/Sun) or HOLIDAY (Mexican public holiday). A holiday falling on a weekend is stored as HOLIDAY',
    "__PROCESSED_DTTM"     TIMESTAMP_NTZ COMMENT 'ETL processing timestamp',
    "__STG_PROCESSED_DTTM" TIMESTAMP_NTZ COMMENT 'Staging processing timestamp'
)
COMMENT = 'Mexican non-business day calendar: weekends + public holidays, 2024-2027. Grain: one row per non-business day. Source of truth for business-day counts (CoR run rate scaling, SLA on weekday-only tables). Appendix B.';


---------------------------------------------------------------------------
-- 2.2 Наполнение календаря.
--
-- Решение по дате, которая одновременно выходной и праздник (например
-- 12.12.2026 — суббота): пишем ОДНУ строку с TYPE = 'HOLIDAY'. На счёт рабочих
-- дней это не влияет (дата нерабочая в любом случае), но запрос «только
-- праздники» из Appendix B тогда не теряет праздники, попавшие на выходные.
---------------------------------------------------------------------------

INSERT INTO ODS.REF.HOLIDAYS ("KEY", "DATE", "TYPE", "__PROCESSED_DTTM", "__STG_PROCESSED_DTTM")
WITH yrs AS (
    SELECT 2024 + SEQ4() AS y FROM TABLE(GENERATOR(ROWCOUNT => 4))
),
-- Пасха по григорианскому алгоритму (Meeus/Jones/Butcher). Считается, а не
-- вписывается руками: подвижные даты Semana Santa иначе протухнут за пределами
-- вписанных лет, и календарь начнёт врать молча.
e1 AS (
    SELECT y, MOD(y, 19) AS a, FLOOR(y / 100) AS b, MOD(y, 100) AS c FROM yrs
),
e2 AS (
    SELECT y, a, b, c, FLOOR(b / 4) AS d, MOD(b, 4) AS ee, FLOOR((b + 8) / 25) AS f FROM e1
),
e3 AS (
    SELECT y, a, b, c, d, ee, f, FLOOR((b - f + 1) / 3) AS g FROM e2
),
e4 AS (
    SELECT y, a, ee, c,
           MOD(MOD(19 * a + b - d - g + 15, 30) + 30, 30) AS h,
           FLOOR(c / 4) AS i, MOD(c, 4) AS k
    FROM e3
),
e5 AS (
    SELECT y, a, h, MOD(MOD(32 + 2 * ee + 2 * i - h - k, 7) + 7, 7) AS l FROM e4
),
easter AS (
    SELECT y,
           DATE_FROM_PARTS(y,
               FLOOR((h + l - 7 * FLOOR((a + 11 * h + 22 * l) / 451) + 114) / 31),
               MOD(h + l - 7 * FLOOR((a + 11 * h + 22 * l) / 451) + 114, 31) + 1) AS easter_dt
    FROM e5
),
hols AS (
    SELECT y, DATE_FROM_PARTS(y, 1, 1)  AS dt FROM yrs                      -- Ano Nuevo
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 5, 1)  FROM yrs                  -- Dia del Trabajo
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 5, 10) FROM yrs                  -- Dia de las Madres
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 9, 16) FROM yrs                  -- Independencia
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 11, 2) FROM yrs                  -- Dia de Muertos
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 12, 12) FROM yrs                 -- Virgen de Guadalupe
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 12, 25) FROM yrs                 -- Navidad
    UNION ALL SELECT y, DATE_FROM_PARTS(y, 12, 1) FROM yrs
              WHERE MOD(y - 2024, 6) = 0                                    -- Inauguracion, раз в 6 лет
    UNION ALL SELECT y, DATEADD(day, MOD(8 - DAYOFWEEKISO(DATE_FROM_PARTS(y, 2, 1)), 7),
                                DATE_FROM_PARTS(y, 2, 1)) FROM yrs          -- Constitucion, 1-й пн февраля
    UNION ALL SELECT y, DATEADD(day, MOD(8 - DAYOFWEEKISO(DATE_FROM_PARTS(y, 3, 1)), 7) + 14,
                                DATE_FROM_PARTS(y, 3, 1)) FROM yrs          -- Benito Juarez, 3-й пн марта
    UNION ALL SELECT y, DATEADD(day, MOD(8 - DAYOFWEEKISO(DATE_FROM_PARTS(y, 11, 1)), 7) + 14,
                                DATE_FROM_PARTS(y, 11, 1)) FROM yrs         -- Revolucion, 3-й пн ноября
    UNION ALL SELECT y, DATEADD(day, -3, easter_dt) FROM easter             -- Jueves Santo
    UNION ALL SELECT y, DATEADD(day, -2, easter_dt) FROM easter             -- Viernes Santo
),
spine AS (
    SELECT DATEADD(day, SEQ4(), DATE '2024-01-01') AS dt
    FROM TABLE(GENERATOR(ROWCOUNT => 1461))
)
SELECT OBJECT_CONSTRUCT('date_serial', DATEDIFF('day', DATE '1970-01-01', s.dt)),
       s.dt,
       CASE WHEN h.dt IS NOT NULL THEN 'HOLIDAY' ELSE 'WEEKEND' END,
       '2026-08-01 03:14:00'::TIMESTAMP_NTZ,
       '2026-08-01 03:02:00'::TIMESTAMP_NTZ
FROM spine s
LEFT JOIN (SELECT DISTINCT dt FROM hols) h ON h.dt = s.dt
WHERE DAYOFWEEKISO(s.dt) IN (6, 7) OR h.dt IS NOT NULL;


---------------------------------------------------------------------------
-- 2.3 RISK_GOV.META.DIM_DATE — служебный спайн.
-- В приложениях его нет; нужен, чтобы логика рабочих дней не переписывалась
-- заново в каждом запросе SLA и run rate.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_GOV.META.DIM_DATE
COMMENT = 'Date spine with Mexican business-day flags derived from ODS.REF.HOLIDAYS. Not from the appendices: internal helper so that SLA and run-rate logic never re-implements the calendar inline.'
AS
WITH spine AS (
    SELECT DATEADD(day, SEQ4(), DATE '2024-01-01') AS dt
    FROM TABLE(GENERATOR(ROWCOUNT => 1461))
),
flagged AS (
    SELECT s.dt,
           DAYOFWEEKISO(s.dt) IN (6, 7)          AS is_weekend,
           COALESCE(h."TYPE" = 'HOLIDAY', FALSE) AS is_holiday,
           h."DATE" IS NULL                      AS is_business_day
    FROM spine s
    LEFT JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.dt
)
SELECT dt                                                     AS date_day,
       is_weekend,
       is_holiday,
       is_business_day,
       DATE_TRUNC('month', dt)                                AS month_start,
       YEAR(dt)                                               AS year_num,
       QUARTER(dt)                                            AS quarter_num,
       MONTH(dt)                                              AS month_num,
       SUM(IFF(is_business_day, 1, 0)) OVER (
           PARTITION BY DATE_TRUNC('month', dt) ORDER BY dt)  AS biz_day_num_in_month,
       SUM(IFF(is_business_day, 1, 0)) OVER (
           PARTITION BY DATE_TRUNC('month', dt))              AS biz_days_in_month,
       LAST_VALUE(IFF(is_business_day, dt, NULL)) IGNORE NULLS OVER (
           PARTITION BY DATE_TRUNC('month', dt) ORDER BY dt
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_biz_day_of_month
FROM flagged;


---------------------------------------------------------------------------
-- 2.4 RISK_GOV.META.REF_PRODUCT — продукты и все их алиасы.
--
-- Приложения описывают расхождение CC / TDC / account_type прозой; здесь оно
-- становится джойнабельным. Reference Data Management сознательно минимальный:
-- задание прямо говорит, что RDM сейчас не приоритет.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_GOV.META.REF_PRODUCT (
    PRODUCT_KEY   COMMENT 'Canonical product key used by the governance layer',
    PRODUCT_RISKS COMMENT 'Value of the PRODUCT_RISKS column - the filter used in RISK_DM.DM.*',
    ACCOUNT_TYPE  COMMENT 'Value of the ACCOUNT_TYPE column - the filter used in RISK_DM.TABLEAU.* and ODS.PC_KERNEL.ACCOUNT',
    ALIASES       COMMENT 'Other codes for the same product found across schemas and documents',
    LABEL         COMMENT 'Human-readable product name',
    IN_BP_CC      COMMENT 'TRUE if the Business Plan counts this product inside "CC". BP CC includes GRZD_CLIPPED, Snowflake keeps them separate (Appendix C)',
    NOTE          COMMENT 'Why this row exists / what breaks without it'
)
COMMENT = 'Single reference for product codes and every alias of them. Not from the appendices: they document the CC/TDC/account_type divergence in prose, this makes it joinable. Reference Data Management, deliberately minimal.'
AS
          SELECT 'CC'::TEXT, 'CC'::TEXT, 'CC'::TEXT, ARRAY_CONSTRUCT('TDC'), 'Credit Card / Tarjeta de Credito'::TEXT, TRUE,
                 'TDC is the CC code in DATA_FOR_DM_REGULATORY_PROVISIONS (Appendix E)'::TEXT
UNION ALL SELECT 'GRZD_CLIPPED', 'GRZD_CLIPPED', 'GRZD_CLIPPED', ARRAY_CONSTRUCT(), 'Garantizada, clipped', TRUE,
                 'Counted inside BP "CC" but a separate PRODUCT_RISKS value in Snowflake - reconciliation trap (Appendix C)'
UNION ALL SELECT 'GRZD', 'GRZD', 'GRZD', ARRAY_CONSTRUCT('Garantizada'), 'Garantizada, secured loan', FALSE, NULL
UNION ALL SELECT 'PL', 'PL', 'PL', ARRAY_CONSTRUCT('Cash Loan'), 'Personal Loan', FALSE,
                 'Legacy cash loan applications live in RISK_LEGACY.DM (Appendix A)'
UNION ALL SELECT 'POS', 'POS', 'POS', ARRAY_CONSTRUCT(), 'Point of Sale', FALSE, NULL;


---------------------------------------------------------------------------
-- 2.5 RISK_GOV.META.REF_SIGN_CONVENTION — знаковые соглашения как данные.
--
-- Appendix C излагает их прозой. Здесь у каждой строки есть CHECK_RULE —
-- предикат, по которому в Фазе 8 автоматически собирается DQ-проверка.
-- Неверный знак не роняет запрос, а молча даёт неверный ответ; ровно поэтому
-- правило должно быть проверяемым, а не прочитанным.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_GOV.META.REF_SIGN_CONVENTION (
    OBJECT_NAME     COMMENT 'Fully qualified table the rule applies to',
    COLUMN_NAME     COMMENT 'Column the rule applies to',
    SIGN_CONVENTION COMMENT 'negative_cost | positive_loss - see the tag RISK_GOV.META.SIGN_CONVENTION',
    MEANING         COMMENT 'What the value means, in business terms',
    SOURCE_DOC      COMMENT 'Where the rule is documented',
    CHECK_RULE      COMMENT 'Boolean SQL predicate that must hold for every non-zero row. Feeds the sign-convention DQ check - the rule is data, not prose'
)
COMMENT = 'Registry of sign conventions across COR columns. Appendix C states these in prose; here they are machine-checkable. A wrong sign silently produces a wrong answer, which is exactly the failure mode this table exists to catch.'
AS
          SELECT 'RISK_DM.DM.STM_COR_CC'::TEXT,       'COR_PRNP'::TEXT,              'negative_cost'::TEXT,
                 'Actual Gen3 management COR on principal, as of current calc date'::TEXT, 'Appendix C'::TEXT, 'COR_PRNP <= 0'::TEXT
UNION ALL SELECT 'RISK_DM.DM.STM_COR_CC',             'COR_PRNP_GEN2',               'negative_cost',
                 'Actual Gen2 management COR on principal',                          'Appendix C', 'COR_PRNP_GEN2 <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR',                         'negative_cost',
                 'Gen3 total management COR',                                        'Appendix H', 'COR <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR_TOTAL',                   'negative_cost',
                 'Gen2 total management COR',                                        'Appendix H', 'COR_TOTAL <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR_1P_FACT',                 'negative_cost',
                 'Gen3 inflow (0 to 1+ DPD) actual',                                 'Appendix H', 'COR_1P_FACT <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR_1P_PREDICT',              'negative_cost',
                 'Gen3 inflow predicted - challenger predictions are already negative', 'Appendix C', 'COR_1P_PREDICT <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR_COLLECTION_FACT',         'negative_cost',
                 'Gen3 collection actual. Nonzero means collection underperforms the model', 'Appendix C', 'COR_COLLECTION_FACT <= 0'
UNION ALL SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER',    'COR_COLLECTION_PREDICT',      'negative_cost',
                 'Gen3 collection predicted',                                        'Appendix C', 'COR_COLLECTION_PREDICT <= 0'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS',       'COR_TOTAL_PREDICT',           'positive_loss',
                 'Predicted expected loss at statement level - POSITIVE, opposite to actuals', 'Appendix C', 'COR_TOTAL_PREDICT >= 0'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_DETAILS',       'BAL_TOTAL_PREDICT',           'positive_loss',
                 'Predicted balance at statement level',                             'Appendix C', 'BAL_TOTAL_PREDICT >= 0'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_AGG',           'COR_TOTAL_PREDICT_LT',        'positive_loss',
                 'Lifetime predicted expected loss',                                 'Appendix G', 'COR_TOTAL_PREDICT_LT >= 0'
UNION ALL SELECT 'RISK_DM.DM.NPV_GEN5_AGG',           'BAL_TOTAL_PREDICT_LT',        'positive_loss',
                 'Lifetime predicted balance',                                       'Appendix G', 'BAL_TOTAL_PREDICT_LT >= 0';


---------------------------------------------------------------------------
-- Приёмка фазы: дословный запрос из Appendix B должен отработать без правок.
-- Факт на 2026: 251 рабочий день, апрель — 20 (30 дней − 8 выходных
-- − Jueves и Viernes Santo 2–3 апреля).
---------------------------------------------------------------------------

-- WITH all_days AS (
--     SELECT DATEADD(day, seq4(), '2026-01-01') AS dt
--     FROM TABLE(GENERATOR(rowcount => 365))
-- )
-- SELECT DATE_TRUNC('month', d.dt) AS month_start, COUNT(*) AS biz_days
-- FROM all_days d
-- LEFT JOIN ods.ref.HOLIDAYS h ON d.dt = h."DATE"
-- WHERE h."DATE" IS NULL
-- GROUP BY 1 ORDER BY 1;
