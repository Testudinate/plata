---------------------------------------------------------------------------
-- Фаза 6. Слой TABLEAU, провизии MxGAAP и скелеты остальных схем.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 6.1 TABLEAU.COR_CHALLENGER — главная таблица слоя.
--
-- Фильтр здесь ACCOUNT_TYPE, а не PRODUCT_RISKS. Приложения A и D говорят, что
-- неверная колонка возвращает пусто «молча» — но в Snowflake обращение
-- к несуществующей колонке даёт ОШИБКУ компиляции, а не пустой результат.
-- Молчаливым промах бывает только если колонка существует. Поэтому ниже
-- добавлена PRODUCT_RISKS: она есть, всегда NULL и помечена как устаревшая —
-- остаток переименования. Это реконструкция, а не буквальная цитата
-- приложения; зафиксировано как допущение.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.TABLEAU.COR_CHALLENGER (
    ACCOUNT_ID             COMMENT 'Account UUID',
    REPORT_DATE            COMMENT 'Calendar date',
    ACCOUNT_TYPE           COMMENT 'CRITICAL: this schema filters on ACCOUNT_TYPE, not PRODUCT_RISKS. Using the DM column name here returns zero rows silently (Appendix A, D)',
    COR                    COMMENT 'Gen3 total management COR. NEGATIVE. Equals COR_1P_FACT + COR_COLLECTION_FACT and EXCLUDES the 0-DPD bucket',
    COR_TOTAL              COMMENT 'Gen2 total management COR. NEGATIVE. Equals COR_DLQ_FACT + COR_0_BUCKET and INCLUDES the 0-DPD bucket - the asymmetry with COR is real',
    COR_1P_FACT            COMMENT 'Gen3 inflow (0 to 1+ DPD) actual. NEGATIVE',
    COR_1P_PREDICT         COMMENT 'Gen3 inflow predicted. Already NEGATIVE, unlike the NPV forecast (Appendix C)',
    COR_COLLECTION_FACT    COMMENT 'Gen3 collection actual. Nonzero means collection underperforms the model - the key diagnostic of Appendix C',
    COR_COLLECTION_PREDICT COMMENT 'Gen3 collection predicted. Already NEGATIVE',
    COR_0_BUCKET           COMMENT 'Provision change on the performing (0-DPD) portfolio. Needed for the bucket decomposition check of Appendix H',
    COR_DLQ_FACT           COMMENT 'Gen2 delinquent component',
    NET_BALANCE_PRNP       COMMENT 'Net principal balance (Gen3)',
    BALANCE_PRNP           COMMENT 'Gross principal balance',
    DLQ_DAYS               COMMENT 'Current DPD',
    PREV_DLQ_DAYS          COMMENT 'Previous day DPD. Drives the inflow-vs-collection split and the finer bucket decomposition (Appendix H)',
    PROVISIONS_DLQ_GEN3    COMMENT 'Gen3 provisions on the delinquent portion'
)
COMMENT = 'Daily COR with Gen3 decomposition. Grain: account_id x report_date. Primary table for comparing Gen2 against Gen3 at a granular level. ALL COR columns are NEGATIVE - negate one side when comparing to NPV forecasts. FILTER ON ACCOUNT_TYPE, not PRODUCT_RISKS. Appendix H.'
AS
SELECT c.account_id, c.report_date, c.product_risks AS account_type,
       c.cor, c.cor_total, c.cor_1p_fact, c.cor_1p_predict,
       c.cor_collection_fact, c.cor_collection_predict,
       c.cor_0_bucket, c.cor_dlq_fact,
       c.balance_net_prnp_gen3 AS net_balance_prnp, c.balance_prnp,
       c.dlq_days, c.prev_dlq_days,
       IFF(c.dlq_days > 0, c.provisions_prnp_gen3, 0) AS provisions_dlq_gen3
FROM RISK_DM.RAW.SYNTH_PANEL_COR c;

-- Ловушка «молчаливого» неверного фильтра.
ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER
    ADD COLUMN PRODUCT_RISKS TEXT
    COMMENT 'DEPRECATED, always NULL. Left behind by the rename to ACCOUNT_TYPE. It exists solely so that WHERE PRODUCT_RISKS = ''CC'' returns zero rows SILENTLY instead of raising an unknown-column error - which is the failure mode Appendix A and D describe. Never populate it; the live filter is ACCOUNT_TYPE.';


---------------------------------------------------------------------------
-- 6.2 CLIP-витрины. Две материализации, запрашиваются напрямую без джойнов.
--
-- Инкремент CLIP считается как фактический COR постклиповых счетов минус то,
-- что дал бы тот же баланс по ставке базовой когорты.
-- IS_CLIP_FREEZE = TRUE — контрольная когорта, для стандартных кривых
-- жизненного цикла её надо отфильтровывать (Appendix H).
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.TABLEAU.CLIP_COR_MONTHLY
COMMENT = 'Materialized CLIP analysis, one row per report_month. Total portfolio CoR, the CLIP incremental part and the base part, in absolute MXN and as annualized rates, with 95% confidence bounds and the CLIP share of total CoR. Queryable directly, no joins needed. Appendix H.'
AS
WITH base AS (
    SELECT c.report_date, c.account_id, c.is_clip_freeze,
           c.cor + c.cor_0_bucket AS cor_gen3_total,
           c.balance_net_prnp_gen3 AS bal,
           (a.gets_clip AND c.report_date >= DATEADD(day, 150 + MOD(ABS(HASH(a.account_seq, 'clipday')), 90), a.utilization_date)) AS post_clip
    FROM RISK_DM.RAW.SYNTH_PANEL_COR c
    JOIN RISK_DM.RAW.SYNTH_ACCOUNTS a ON a.account_id = c.account_id
    WHERE c.product_risks = 'CC'
),
monthly AS (
    SELECT DATE_TRUNC('month', report_date) AS report_month,
           SUM(cor_gen3_total) AS total_cor, SUM(bal) AS total_bal,
           SUM(IFF(post_clip, cor_gen3_total, 0)) AS clip_cor,
           SUM(IFF(post_clip, bal, 0))            AS clip_bal,
           SUM(IFF(NOT post_clip, cor_gen3_total, 0)) AS base_cor,
           SUM(IFF(NOT post_clip, bal, 0))            AS base_bal,
           COUNT(DISTINCT account_id) AS n_accounts,
           COUNT(DISTINCT IFF(post_clip, account_id, NULL)) AS n_clip_accounts,
           STDDEV(cor_gen3_total) AS sd_cor, COUNT(*) AS n_obs
    FROM base GROUP BY 1
)
SELECT report_month,
       ROUND(total_cor, 2) AS total_cor_mxn,
       ROUND(base_cor, 2)  AS base_cor_mxn,
       ROUND(clip_cor - clip_bal * (base_cor / NULLIF(base_bal, 0)), 2) AS clip_incr_cor_mxn,
       ROUND(-total_cor / NULLIF(total_bal, 0) * 365 * 100, 4) AS total_cor_pct_annual,
       ROUND(-base_cor  / NULLIF(base_bal, 0)  * 365 * 100, 4) AS base_cor_pct_annual,
       ROUND(-(clip_cor - clip_bal * (base_cor / NULLIF(base_bal, 0)))
             / NULLIF(clip_bal, 0) * 365 * 100, 4) AS clip_incr_cor_pct_annual,
       ROUND(-(clip_cor - clip_bal * (base_cor / NULLIF(base_bal, 0)))
             / NULLIF(clip_bal, 0) * 365 * 100
             - 1.96 * sd_cor * SQRT(n_obs) / NULLIF(clip_bal, 0) * 365 * 100, 4) AS clip_incr_cor_pct_lo95,
       ROUND(-(clip_cor - clip_bal * (base_cor / NULLIF(base_bal, 0)))
             / NULLIF(clip_bal, 0) * 365 * 100
             + 1.96 * sd_cor * SQRT(n_obs) / NULLIF(clip_bal, 0) * 365 * 100, 4) AS clip_incr_cor_pct_hi95,
       ROUND((clip_cor - clip_bal * (base_cor / NULLIF(base_bal, 0)))
             / NULLIF(total_cor, 0) * 100, 2) AS clip_share_of_total_cor_pct,
       n_accounts, n_clip_accounts,
       ROUND(total_bal, 2) AS total_balance_mxn,
       ROUND(clip_bal, 2)  AS clip_balance_mxn
FROM monthly;

CREATE OR REPLACE TABLE RISK_DM.TABLEAU.CLIP_COR_VINTAGE
COMMENT = 'Materialized CLIP lifecycle curves. Grain: clip_vintage x stmt_after_clip x is_clip_freeze. ALWAYS filter IS_CLIP_FREEZE = FALSE for standard lifecycle curves - the freeze cohort is a control group and mixing it in flattens the curve (Appendix H). VINTAGE_MATURITY marks how far the cohort has run: young / developing / mature.'
AS
WITH post AS (
    SELECT c.account_id, c.report_date, c.is_clip_freeze,
           DATEADD(day, 150 + MOD(ABS(HASH(a.account_seq, 'clipday')), 90), a.utilization_date) AS clip_date,
           c.cor + c.cor_0_bucket AS cor_gen3_total, c.balance_net_prnp_gen3 AS bal
    FROM RISK_DM.RAW.SYNTH_PANEL_COR c
    JOIN RISK_DM.RAW.SYNTH_ACCOUNTS a ON a.account_id = c.account_id
    WHERE c.product_risks = 'CC' AND a.gets_clip
),
shaped AS (
    SELECT DATE_TRUNC('month', clip_date) AS clip_vintage,
           FLOOR(DATEDIFF('day', clip_date, report_date) / 30) AS stmt_after_clip,
           is_clip_freeze, account_id, cor_gen3_total, bal
    FROM post WHERE report_date >= clip_date
),
agg AS (
    SELECT clip_vintage, stmt_after_clip, is_clip_freeze,
           AVG(cor_gen3_total) AS avg_incr_cor, AVG(bal) AS avg_incr_balance,
           SUM(cor_gen3_total) AS sum_cor, SUM(bal) AS sum_bal,
           STDDEV(cor_gen3_total) AS sd_cor, COUNT(*) AS n_obs,
           COUNT(DISTINCT account_id) AS n_accounts
    FROM shaped WHERE stmt_after_clip BETWEEN 0 AND 17
    GROUP BY 1, 2, 3
)
SELECT clip_vintage, stmt_after_clip, is_clip_freeze,
       ROUND(avg_incr_cor, 4) AS avg_incr_cor,
       ROUND(avg_incr_balance, 2) AS avg_incr_balance,
       ROUND(-sum_cor / NULLIF(sum_bal, 0) * 365 * 100, 4) AS incr_cor_pct_annual,
       ROUND(SUM(-sum_cor) OVER (PARTITION BY clip_vintage, is_clip_freeze ORDER BY stmt_after_clip
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_cor_incr,
       ROUND(-sum_cor / NULLIF(sum_bal, 0) * 365 * 100
             - 1.96 * sd_cor * SQRT(n_obs) / NULLIF(sum_bal, 0) * 365 * 100, 4) AS incr_cor_pct_lo95,
       ROUND(-sum_cor / NULLIF(sum_bal, 0) * 365 * 100
             + 1.96 * sd_cor * SQRT(n_obs) / NULLIF(sum_bal, 0) * 365 * 100, 4) AS incr_cor_pct_hi95,
       n_accounts, n_obs,
       CASE WHEN MAX(stmt_after_clip) OVER (PARTITION BY clip_vintage, is_clip_freeze) >= 12 THEN 'mature'
            WHEN MAX(stmt_after_clip) OVER (PARTITION BY clip_vintage, is_clip_freeze) >= 6  THEN 'developing'
            ELSE 'young' END AS vintage_maturity
FROM agg;


---------------------------------------------------------------------------
-- 6.3 Провизии MxGAAP.
--
-- В отличие от управленческих резервов (Gen2/Gen3, только principal), MxGAAP
-- покрывает весь EAD = principal + начисленные проценты. Разложение на yield
-- и principal — по формуле из Appendix G; проверено, ошибка ровно 0.
--
-- Ставки разгоняются до 100% по 13 бакетам 30..390. В данных заполнены 8
-- из 13: эпизоды редко доживают до 240+ дней, потому что списание происходит
-- на ближайший конец квартала после 120 дней. Схема поддерживает все 13.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_PROV.PROV.MXGAAP_PROV_CC
COMMENT = 'MxGAAP regulatory provisions for CC. Monthly snapshot per account. Unlike management provisions (Gen2/Gen3, principal only), MxGAAP covers total EAD = principal + accrued interest. Decompose with provision_rate = PROVISIONS / EAD, then yield_prov = rate * GINTEREST_BALANCE_MXGAAP_ADJ and prnp_prov = rate * BALANCE_MXGAAP (Appendix G). Rates ramp to 100% across the 13 DPD buckets 30..390 (Appendix C).'
AS
WITH month_end AS (
    SELECT c.*, d.last_biz_day_of_month
    FROM RISK_DM.RAW.SYNTH_PANEL_COR c
    JOIN RISK_GOV.META.DIM_DATE d ON d.date_day = c.report_date
    WHERE c.product_risks IN ('CC', 'GRZD_CLIPPED') AND c.report_date = d.last_biz_day_of_month
),
bucketed AS (
    SELECT account_id, report_date, product_risks, dlq_days, balance_prnp,
           IFF(dlq_days = 0, 0, LEAST(390, CEIL(dlq_days / 30.0) * 30)) AS dpd_bucket,
           balance_prnp AS balance_mxgaap,
           ROUND(balance_prnp * 0.085, 2) AS ginterest_balance_mxgaap_adj
    FROM month_end
)
SELECT account_id, report_date, product_risks, dlq_days, dpd_bucket,
       balance_mxgaap AS BALANCE_MXGAAP,
       ginterest_balance_mxgaap_adj AS GINTEREST_BALANCE_MXGAAP_ADJ,
       ROUND(balance_mxgaap + ginterest_balance_mxgaap_adj, 2) AS EAD,
       ROUND((balance_mxgaap + ginterest_balance_mxgaap_adj) *
             CASE dpd_bucket WHEN 0 THEN 0.005 WHEN 30 THEN 0.10 WHEN 60 THEN 0.25
                             WHEN 90 THEN 0.45 WHEN 120 THEN 0.60 WHEN 150 THEN 0.72
                             WHEN 180 THEN 0.82 WHEN 210 THEN 0.88 WHEN 240 THEN 0.92
                             WHEN 270 THEN 0.95 WHEN 300 THEN 0.97 WHEN 330 THEN 0.98
                             WHEN 360 THEN 0.99 ELSE 1.00 END, 2) AS PROVISIONS
FROM bucketed;

CREATE OR REPLACE TABLE RISK_PROV.PROV.ADD_PROV
COMMENT = 'CNBV additional provisions for accounts with an incomplete credit assessment - no bureau report or no final scoring. Appendix E.'
AS
SELECT a.account_id, a.product_risks, DATE '2026-06-30' AS report_date,
       CASE WHEN MOD(ABS(HASH(a.account_seq, 'addprov')), 100) < 2 THEN 'NO_BUREAU_REPORT'
            ELSE 'NO_FINAL_SCORING' END AS reason,
       ROUND(a.credit_limit_orig * 0.4 * 0.25, 2) AS add_prov_amount
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
WHERE MOD(ABS(HASH(a.account_seq, 'addprov')), 100) < 5;

-- Здесь и только здесь продукт CC называется TDC — расхождение референсных
-- данных из Appendix E. Разрешается через RISK_GOV.META.REF_PRODUCT.ALIASES.
CREATE OR REPLACE TABLE RISK_PROV.PROV.DATA_FOR_DM_REGULATORY_PROVISIONS
COMMENT = 'Input feed for regulatory provisions. NOTE the product code: CC is spelled TDC (Tarjeta de Credito) here and nowhere else - the reference-data divergence named in Appendix E. Resolve it through RISK_GOV.META.REF_PRODUCT.ALIASES.'
AS
SELECT a.account_id,
       CASE a.product_risks WHEN 'CC' THEN 'TDC' ELSE a.product_risks END AS product_code,
       DATE '2026-06-30' AS report_date,
       ROUND(0.05 + MOD(ABS(HASH(a.account_seq, 'eprc')), 90) / 100.0, 4) AS eprc,
       IFF(MOD(ABS(HASH(a.account_seq, 'califica')), 100) < 88, 'CALIFICA', 'INTERNAL_MODEL') AS eprc_source
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
WHERE a.product_risks IN ('CC', 'GRZD_CLIPPED');


---------------------------------------------------------------------------
-- 6.4 DDS.STM_FACT_FORECAST — предджойненная материализация.
-- Appendix D говорит, что ad-hoc джойн предпочтительнее: он оставляет
-- дедупликацию и фильтрацию под контролем вызывающего. Таблица создана, чтобы
-- расхождение двух путей было видимым, а не гипотетическим.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DDS.STM_FACT_FORECAST
COMMENT = 'Pre-joined statement actuals against the latest gen5v1 forecast. Convenience materialization: Appendix D states the ad-hoc join is preferred because it keeps dedup and filtering under the caller control. Kept here so the divergence between the two paths is visible rather than hypothetical.'
AS
WITH latest AS (
    SELECT account_id, statement_num, report_month, cor_total_predict, bal_total_predict,
           cor_total_var, bal_total_var
    FROM RISK_DM.DM.NPV_GEN5_DETAILS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY account_id, statement_num ORDER BY report_month DESC) = 1
)
SELECT a.account_id, a.product_risks, a.statement_num, a.end_date, a.util_month,
       a.cor_prnp, a.avg_balance_prnp_net,
       f.report_month AS forecast_report_month,
       f.cor_total_predict, f.bal_total_predict, f.cor_total_var, f.bal_total_var
FROM RISK_DM.DM.STM_COR_CC a
LEFT JOIN latest f ON f.account_id = a.account_id AND f.statement_num = a.statement_num;


---------------------------------------------------------------------------
-- 6.5 Оставшиеся витрины DM: заявки, скоринг и weekday-only таблицы.
-- Полные тексты — в выполненных стейтментах; здесь ключевое:
--   APPLICATIONS       — у отклонённых заявок ACCOUNT_ID = NULL, джойн
--                        к счетам без учёта этого молча теряет реджекты
--   SCORING_LOG        — четыре стадии на заявку с префиксами из Appendix G
--   CLIP_STATEMENTS    — statement после CLIP, weekday-only
--   STM_GRZD           — статементы GRZD, weekday-only
--   NPV_NAIVE_DETAILS  — наивный бейзлайн, weekday-only
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 6.6 Скелеты остальных схем: ODS.PC_TARIFFS / PC_APP / PF_LOANS / PF_GL,
-- RISK_LEGACY.DM.PD005_BY_STAGES, RISK_RDS.DDS.PORTFOLIO_FEATURES,
-- CREDIT_PROD.DBT.CC_CASHFLOWS, COLLECTION_PROD.DBT.AGENCY_TEST_GROUPS,
-- PAYMENTS_PROD.DBT.EMART_TRANSACTIONS, POS_PROD.DDS.POS_LOANS.
--
-- Они нужны, чтобы карта схем из Appendix A не врала, а не для расчётов.
-- RISK_LEGACY.DM — ДРУГАЯ схема, чем RISK_DM.DM, при одинаковом имени;
-- эта неоднозначность названа в Appendix A и воспроизведена намеренно.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- ПРИЁМКА ФАЗЫ 6. Фактические значения:
--
--   Appendix H, декомпозиция по prev_dlq_days сходится с тоталом   остаток 0
--   Appendix A/D, фильтр по product_risks в tableau                0 строк, без ошибки
--   Appendix G, разложение MxGAAP на yield и principal             ошибка 0
--   Appendix C, заполненных DPD-бакетов                            8 из 13
--   Appendix H, строк с is_clip_freeze = TRUE                      169
--   Appendix H, классы зрелости винтажей                           young, developing, mature
--   Appendix E, записей с кодом TDC                                3000
--   Appendix B/D, выходные в end_date weekday-only таблиц          0
--
-- Итог песочницы: 47 таблиц в 21 схеме, ~9.2 млн строк.
---------------------------------------------------------------------------
