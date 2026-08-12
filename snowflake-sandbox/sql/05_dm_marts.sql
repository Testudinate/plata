---------------------------------------------------------------------------
-- Фаза 5. Витрины DM и наполнение ODS.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
--
-- Всё здесь — проекции панели из фазы 4. Порядок: сначала ODS (мастер счетов
-- и статементы), потом DM.
--
-- ВАЖНОЕ О ФАЗЕ. Три ошибки, найденные проверкой дословными запросами из
-- приложений, а не чтением собственного кода:
--
-- 1. COR_PRNP в stm_cor_cc сначала содержал только инфлоу и коллекшн, без
--    0-бакета. 86% статементов получали ровно нулевой COR, запрос из
--    Appendix D отбрасывал их вместе с 86% баланса, и COR% подскакивал
--    с 10.6 до 61. Исправлено в фазе 4: там теперь полный Gen3-тотал.
--
-- 2. Прогноз NPV строился от ABS(cor_prnp). У части статементов COR
--    положительный — это высвобождение резерва при излечении, и ABS
--    превращал высвобождение в предсказанный убыток. Хуже того, прогноз
--    занулялся ровно там, где факт благоприятен, а фильтр
--    cor_total_predict != 0 из Appendix D выбрасывал эту половину портфеля.
--    Исправлено: ожидаемая потеря положительна всегда и не зависит от знака
--    факта, веса откалиброваны по замеру, а не подобраны.
--
-- 3. Join "COR at inflow" из Appendix C возвращал 0 строк: просрочка
--    начиналась через день после due date, а приложение предполагает, что
--    dlq_first_dt совпадает с end_date выписки. Исправлено в фазе 4.
--
-- Ни одну из трёх нельзя было заметить, глядя на схему: таблицы выглядели
-- правильно и наполнялись без ошибок. Их видно только тогда, когда
-- документированный запрос гоняется по данным дословно.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 5.1 Наполнение ODS. TRUNCATE + INSERT, потому что структуры созданы в фазе 3.
---------------------------------------------------------------------------

TRUNCATE TABLE ODS.PC_KERNEL."ACCOUNT";
TRUNCATE TABLE ODS.PF_ENGINE.STATEMENTS;

INSERT INTO ODS.PC_KERNEL."ACCOUNT" (ID, CLIENT_ID, ACCOUNT_TYPE, ACCOUNT_STATE, OPEN_DTTM, CREDIT_LIMIT, "__PROCESSED_DTTM")
WITH lim AS (
    SELECT account_seq, credit_limit,
           ROW_NUMBER() OVER (PARTITION BY account_seq ORDER BY report_date DESC) AS rn
    FROM RISK_DM.RAW.SYNTH_PANEL
)
SELECT a.account_id, a.client_id, a.product_risks,
       CASE WHEN EXISTS (SELECT 1 FROM RISK_DM.RAW.SYNTH_EPISODES e
                         WHERE e.account_seq = a.account_seq AND e.is_wo) THEN 'WRITTEN_OFF'
            WHEN MOD(ABS(HASH(a.account_seq, 'state')), 100) < 4 THEN 'CLOSED'
            WHEN MOD(ABS(HASH(a.account_seq, 'state')), 100) < 7 THEN 'BLOCKED'
            ELSE 'ACTIVE' END,
       -- Локальное время открытия 14:00-23:00 Mexico City, в таблице лежит UTC
       -- (+6). Поэтому у 59.4% счетов DATE(OPEN_DTTM) на день БОЛЬШЕ, чем
       -- UTILIZATION_DATE в DM: ловушка таймзон из Appendix F, замеряно.
       DATEADD(hour, 6 + 14 + MOD(ABS(HASH(a.account_seq, 'hour')), 10), a.utilization_date::TIMESTAMP_NTZ),
       COALESCE(l.credit_limit, a.credit_limit_orig),
       '2026-07-01 02:10:00'::TIMESTAMP_NTZ
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
LEFT JOIN lim l ON l.account_seq = a.account_seq AND l.rn = 1;

INSERT INTO ODS.USER_MGMT.USER_DATA (CLIENT_ID, GENDER, BIRTHDAY, STATE, "__PROCESSED_DTTM")
SELECT c.client_id,
       IFF(MOD(ABS(HASH(c.client_id, 'gender')), 100) < 52, 'F', 'M'),
       DATEADD(day, -(21 * 365 + MOD(ABS(HASH(c.client_id, 'age')), 44 * 365)), DATE '2026-06-30'),
       GET(ARRAY_CONSTRUCT('Ciudad de Mexico','Estado de Mexico','Jalisco','Nuevo Leon','Puebla',
                           'Guanajuato','Veracruz','Chihuahua','Michoacan','Oaxaca','Queretaro',
                           'Yucatan','Baja California','Sinaloa','Coahuila','Sonora'),
           MOD(ABS(HASH(c.client_id, 'state')), 16))::TEXT,
       '2026-07-01 02:12:00'::TIMESTAMP_NTZ
FROM (SELECT DISTINCT client_id FROM RISK_DM.RAW.SYNTH_ACCOUNTS) c;

INSERT INTO ODS.PF_ENGINE.STATEMENTS (STATEMENT_ID, ACCOUNT_ID, STATEMENT_NUM, STATEMENT_DTTM, DUE_DTTM, CLOSING_BALANCE, MIN_PAYMENT, "__PROCESSED_DTTM")
SELECT s.account_seq * 100 + s.statement_num, s.account_id, s.statement_num,
       -- Отсечка выписки в 23:00 по Mexico City -> в UTC это уже следующий день.
       DATEADD(hour, 6 + 23, s.end_date::TIMESTAMP_NTZ),
       DATEADD(hour, 6 + 23, s.due_date::TIMESTAMP_NTZ),
       COALESCE(p.balance_prnp, 0), ROUND(COALESCE(p.balance_prnp, 0) * 0.05, 2),
       '2026-07-01 02:20:00'::TIMESTAMP_NTZ
FROM RISK_DM.RAW.SYNTH_STATEMENTS s
LEFT JOIN RISK_DM.RAW.SYNTH_PANEL p ON p.account_seq = s.account_seq AND p.report_date = s.end_date
WHERE s.product_risks IN ('CC', 'GRZD_CLIPPED');


---------------------------------------------------------------------------
-- 5.2 DM.ACCOUNTS — мастер витрины.
-- Колонки FIRST_UTILIZATION_DATE здесь намеренно НЕТ: Appendix B прямо
-- предупреждает, что её не существует и легаси-код, который к ней обращается,
-- ошибочен. Воспроизводим отсутствие, а не «чиним».
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.ACCOUNTS
COMMENT = 'Account master of the Data Mart. Enrich any DM table with product_risks, account_state and origination date by joining on ACCOUNT_ID (Appendix F). NOTE: there is deliberately no FIRST_UTILIZATION_DATE column - Appendix B states it does not exist and legacy code referencing it is wrong.'
AS
WITH last_row AS (
    SELECT account_seq, credit_limit,
           ROW_NUMBER() OVER (PARTITION BY account_seq ORDER BY report_date DESC) AS rn
    FROM RISK_DM.RAW.SYNTH_PANEL
)
SELECT a.account_id, a.client_id, a.product_risks,
       CASE WHEN EXISTS (SELECT 1 FROM RISK_DM.RAW.SYNTH_EPISODES e
                         WHERE e.account_seq = a.account_seq AND e.is_wo) THEN 'WRITTEN_OFF'
            WHEN MOD(ABS(HASH(a.account_seq, 'state')), 100) < 4 THEN 'CLOSED'
            WHEN MOD(ABS(HASH(a.account_seq, 'state')), 100) < 7 THEN 'BLOCKED'
            ELSE 'ACTIVE' END                                  AS account_state,
       a.utilization_date,
       DATE_TRUNC('month', a.utilization_date)                 AS util_month,
       COALESCE(lr.credit_limit, a.credit_limit_orig)::FLOAT   AS credit_limit,
       a.credit_limit_orig::FLOAT                              AS credit_limit_orig,
       a.risk_beh_type, a.gets_clip AS has_clip, a.is_clip_freeze
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
LEFT JOIN last_row lr ON lr.account_seq = a.account_seq AND lr.rn = 1;


---------------------------------------------------------------------------
-- 5.3 DM.UTILIZATIONS и DM.LIMIT_ACTIONS.
-- В LIMIT_ACTIONS событие origination и событие CLIP НЕ размечены флагом:
-- их различают правилом из Appendix D (bs_day <= utilization_date + 100).
-- Замер: 796 событий проходят как CLIP.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.UTILIZATIONS
COMMENT = 'First utilization per account. UTILIZATION_DATE is the vintage date convention for the whole warehouse (Appendix B). Grain: one row per account.'
AS
SELECT a.account_id, a.product_risks, a.utilization_date,
       DATE_TRUNC('month', a.utilization_date) AS util_month,
       ROUND(a.credit_limit_orig * 0.4, 2)::FLOAT AS utilization_amount
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a;

CREATE OR REPLACE TABLE RISK_DM.DM.LIMIT_ACTIONS
COMMENT = 'Credit limit events. Origination and CLIP are NOT flagged in the data - they are told apart by the rule from Appendix D: bs_day <= utilization_date + 100 is origination, later is CLIP. Reproducing that ambiguity is the point.'
AS
SELECT a.account_id, a.product_risks, a.utilization_date AS bs_day,
       0::FLOAT AS limit_before, a.credit_limit_orig::FLOAT AS limit_after
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
UNION ALL
SELECT a.account_id, a.product_risks,
       DATEADD(day, 150 + MOD(ABS(HASH(a.account_seq, 'clipday')), 90), a.utilization_date),
       a.credit_limit_orig::FLOAT, ROUND(a.credit_limit_orig * 1.4, 2)::FLOAT
FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
WHERE a.gets_clip
  AND DATEADD(day, 150 + MOD(ABS(HASH(a.account_seq, 'clipday')), 90), a.utilization_date) <= DATE '2026-06-30';


---------------------------------------------------------------------------
-- 5.4 DM.PORTFOLIO_COR — состав колонок и типы дословно по Appendix B.
-- STATEMENT_ID здесь TEXT, а в ODS.PF_ENGINE.STATEMENTS — INTEGER.
-- Расхождение типов между слоями сохранено намеренно: это материал для Part 1.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.PORTFOLIO_COR (
    ACCOUNT_ID            COMMENT 'Account UUID',
    REPORT_DATE           COMMENT 'Calendar date. Available on weekends - unlike the statement-based tables',
    PRODUCT_RISKS         COMMENT 'Product filter for DM tables: CC, GRZD_CLIPPED, PL, POS, GRZD. TABLEAU tables filter on ACCOUNT_TYPE instead',
    BALANCE_PRNP          COMMENT 'Gross principal balance',
    BALANCE_NET_PRNP      COMMENT 'Net principal balance, default generation (Gen2)',
    BALANCE_NET_PRNP_GEN2 COMMENT 'Gen2 net balance',
    BALANCE_NET_PRNP_GEN3 COMMENT 'Gen3 net balance',
    CREDIT_LIMIT          COMMENT 'Credit limit on the report date, after CLIP if any',
    DLQ_FIRST_DT          COMMENT 'First delinquency date of the CURRENT episode. NULL when performing. Join report_date = dlq_first_dt = stm_cor_cc.end_date to get provision at inflow (Appendix C)',
    DPD                   COMMENT 'Days past due',
    PROVISIONS_PRNP       COMMENT 'Provision on principal, default generation (Gen2 - the official production model per Appendix G)',
    PROVISIONS_PRNP_GEN2  COMMENT 'Gen2 provision stock',
    PROVISIONS_PRNP_GEN3  COMMENT 'Gen3 provision stock. Frozen at dlq_first_dt this is COR at inflow (Appendix C)',
    DLQ_BALANCE           COMMENT 'Delinquent balance',
    CURRENT_STATEMENT_NUM COMMENT 'Statement number in force on the report date',
    STATEMENT_ID          COMMENT 'Statement identifier. TEXT here, INTEGER in ODS.PF_ENGINE.STATEMENTS - the type diverges across layers (Appendix B vs F)',
    RISK_BEH_TYPE         COMMENT 'Behavioural segment'
)
COMMENT = 'Daily COR at account level. Grain: account_id x report_date. Filter on PRODUCT_RISKS. Freshness T-1, available on weekends. Appendix B.'
AS
SELECT c.account_id, c.report_date, c.product_risks,
       c.balance_prnp::NUMBER(18,2), c.balance_net_prnp_gen2::FLOAT, c.balance_net_prnp_gen2::FLOAT,
       c.balance_net_prnp_gen3::FLOAT, c.credit_limit::FLOAT, c.dlq_first_dt, c.dlq_days::NUMBER(10,0),
       c.provisions_prnp_gen2::FLOAT, c.provisions_prnp_gen2::FLOAT, c.provisions_prnp_gen3::FLOAT,
       c.dlq_balance::NUMBER(18,2), c.current_statement_num::NUMBER(10,0),
       IFF(c.current_statement_num > 0, (c.account_seq * 100 + c.current_statement_num)::TEXT, NULL),
       c.risk_beh_type
FROM RISK_DM.RAW.SYNTH_PANEL_COR c;


---------------------------------------------------------------------------
-- 5.5 DM.PORTFOLIO_BS — тот же костяк плюс yield-разбивка.
-- Управленческие резервы (Gen2/Gen3) считаются только на principal, поэтому
-- yield-часть живёт здесь и отсутствует в PORTFOLIO_COR (Appendix G).
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.PORTFOLIO_BS
COMMENT = 'Daily balances and provisions. Grain: account_id x report_date. Same backbone as PORTFOLIO_COR plus the yield splits and behavioural segmentation. Appendix B.'
AS
SELECT c.account_id, c.report_date, c.product_risks,
       c.balance_prnp, c.balance_net_prnp_gen2 AS balance_net_prnp,
       ROUND(c.balance_prnp * 0.085, 2)::FLOAT AS balance_yield,
       ROUND(c.balance_net_prnp_gen2 + c.balance_prnp * 0.085
             - c.balance_prnp * 0.085 * IFF(c.dlq_days = 0, 0.01, 0.45), 2)::FLOAT AS balance_net,
       ROUND(c.balance_prnp * 0.085 * (1 - IFF(c.dlq_days = 0, 0.01, 0.45)), 2)::FLOAT AS balance_net_yield,
       ROUND(c.provisions_prnp_gen2 + c.balance_prnp * 0.085 * IFF(c.dlq_days = 0, 0.01, 0.45), 2)::FLOAT AS provisions,
       c.provisions_prnp_gen2 AS provisions_prnp,
       ROUND(c.balance_prnp * 0.085 * IFF(c.dlq_days = 0, 0.01, 0.45), 2)::FLOAT AS provisions_yield,
       c.credit_limit, c.dlq_days AS dpd, c.dlq_first_dt,
       c.risk_beh_type AS beh_type,
       c.risk_beh_type || '_' || CASE WHEN c.dlq_days = 0 THEN 'current'
                                      WHEN c.dlq_days <= 30 THEN 'dpd1_30'
                                      WHEN c.dlq_days <= 60 THEN 'dpd31_60'
                                      WHEN c.dlq_days <= 90 THEN 'dpd61_90'
                                      ELSE 'dpd90plus' END AS beh_type_detailed,
       c.current_statement_num
FROM RISK_DM.RAW.SYNTH_PANEL_COR c;


---------------------------------------------------------------------------
-- 5.6 Статементные витрины.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.STM_COR_CC
COMMENT = 'Statement-level management COR for CC. Grain: account_id x statement_num. Filter PRODUCT_RISKS = CC. END_DATE holds business days only. COR_PRNP is the Gen3 TOTAL as of the current calculation date and is NEGATIVE. No inflow/collection decomposition here - use TABLEAU.COR_CHALLENGER (Appendix B). Statement 1 always carries zero COR.'
AS
SELECT s.account_id, s.product_risks, s.statement_num, s.end_date, s.util_month, s.utilization_date,
       s.cor_prnp, s.cor_prnp_gen2, s.avg_balance_prnp_net, s.avg_balance_prnp,
       s.dpd1_flg, s.dpd1_balance_prnp, s.max_dlq_days, s.dlq_first_dt
FROM RISK_DM.RAW.SYNTH_STM_COR s
WHERE s.product_risks IN ('CC', 'GRZD_CLIPPED');

CREATE OR REPLACE TABLE RISK_DM.DM.STM_CC
COMMENT = 'Statement-level CC metrics. Grain: account_id x statement_num. END_DATE is weekday-only. This table lags several days behind PORTFOLIO_COR - see DM.ETL_LOG. Appendix B.'
AS
SELECT s.account_id, s.product_risks, s.statement_num, s.end_date,
       (s.account_seq * 100 + s.statement_num)::TEXT AS statement_id,
       ROUND(s.avg_balance_prnp, 2) AS closing_balance,
       ROUND(s.avg_balance_prnp * 0.05, 2) AS min_payment,
       ROUND(s.avg_balance_prnp * 0.085 / 12, 2) AS yield_accrued,
       s.cor_prnp AS cor, s.max_dlq_days AS dlq_days
FROM RISK_DM.RAW.SYNTH_STM_COR s
WHERE s.product_risks IN ('CC', 'GRZD_CLIPPED');


---------------------------------------------------------------------------
-- 5.7 NPV Gen5v1.
--
-- Три снимка report_month на каждую пару account x statement — поэтому любой
-- join к факту обязан дедуплицировать через QUALIFY (Appendix D).
-- 23.7% статементов без прогноза: все первые плюс 15% прочих.
-- В снимке 2026-06 — пересчёт модели: EL LT сдвинут на 35% для винтажей
-- первого полугодия 2025. Это материал для Part 3.
--
-- NPV_GEN5_PV_DETAILS НЕ создаётся: она дропнута (Appendix G), её колонки
-- влиты сюда. Запрос к ней должен падать — это демонстрация ломающего
-- изменения.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.NPV_GEN5_DETAILS
COMMENT = 'Gen5v1 statement-level predictions. Grain: account_id x statement_num x report_month - SEVERAL snapshots exist per account and statement, so any join to actuals must dedupe with QUALIFY ROW_NUMBER() on the latest report_month (Appendix D). COR_TOTAL_PREDICT and BAL_TOTAL_PREDICT are POSITIVE, opposite to the negative actuals. Roughly 15% of statements plus all first statements carry no forecast at all. The 2026-06 snapshot carries a model re-estimation: EL LT shifted materially for the 2025-01..2025-06 vintages. Columns from the dropped NPV_GEN5_PV_DETAILS are merged in here (Appendix G).'
AS
WITH snaps AS (
    SELECT DATE '2025-12-01' AS report_month UNION ALL
    SELECT DATE '2026-03-01' UNION ALL SELECT DATE '2026-06-01'
),
base AS (
    SELECT s.account_id, s.account_seq, s.product_risks, s.statement_num, s.end_date, s.util_month,
           -- Веса откалиброваны по замеру за 12 месяцев (июль 2025 - июнь 2026):
           --   gross loss 0.020112/мес, net COR 0.008178/мес
           --   0.30 * 0.020112 + 0.70 * 0.00365 = 0.00859 -> прогноз примерно
           --   на 5% выше факта, то есть портфель идёт "лучше плана".
           -- Ожидаемая потеря положительна ВСЕГДА: модель смотрит вперёд и не
           -- знает, что счёт в этом месяце высвободит резерв.
           0.30 * GREATEST(0, -s.cor_prnp) + 0.70 * s.avg_balance_prnp_net * 0.00365 AS expected_loss,
           s.avg_balance_prnp_net AS bal, sn.report_month
    FROM RISK_DM.RAW.SYNTH_STM_COR s
    CROSS JOIN snaps sn
    WHERE s.product_risks IN ('CC', 'GRZD_CLIPPED')
),
scored AS (
    SELECT b.*,
           0.75 + MOD(ABS(HASH(b.account_seq, b.statement_num, b.report_month, 'f')), 51) / 100.0 AS f_cor,
           0.90 + MOD(ABS(HASH(b.account_seq, b.statement_num, b.report_month, 'b')), 21) / 100.0 AS f_bal,
           IFF(b.report_month = DATE '2026-06-01'
               AND b.util_month BETWEEN DATE '2025-01-01' AND DATE '2025-06-01', 1.35, 1.0) AS recalib,
           (b.statement_num = 1
            OR MOD(ABS(HASH(b.account_seq, b.statement_num, 'nofc')), 100) < 15) AS no_forecast
    FROM base b
)
SELECT account_id, product_risks, statement_num, end_date, util_month, report_month,
       IFF(no_forecast, NULL, ROUND(expected_loss * f_cor * recalib, 2))          AS cor_total_predict,
       IFF(no_forecast, NULL, ROUND(bal * f_bal, 2))                              AS bal_total_predict,
       IFF(no_forecast, NULL, ROUND(POWER(expected_loss * f_cor * recalib * 0.30, 2), 2)) AS cor_total_var,
       IFF(no_forecast, NULL, ROUND(POWER(bal * f_bal * 0.12, 2), 2))             AS bal_total_var,
       IFF(no_forecast, NULL, ROUND(expected_loss * f_cor * recalib * 0.85, 2))   AS cor_orig_predict,
       IFF(no_forecast, NULL, ROUND(bal * f_bal * 0.85, 2))                       AS bal_orig_predict,
       IFF(no_forecast, NULL, ROUND(0.85 + MOD(ABS(HASH(account_id, statement_num, 'ac')), 15) / 100.0, 4)) AS active_clients_predict,
       IFF(no_forecast, NULL, ROUND(bal * 0.012, 2))                              AS opex_predict,
       IFF(no_forecast, NULL, ROUND(bal * 0.021, 2))                              AS funding_predict,
       0.62::FLOAT                                                                AS debt_funding_share
FROM scored;

CREATE OR REPLACE TABLE RISK_DM.DM.NPV_GEN5_AGG
COMMENT = 'Gen5v1 account-level aggregation. The lifetime cutoff statement is 12. EL LT computed from this table equals the DETAILS formula at the cutoff statement (Appendix G) - but only if DETAILS is deduped to the latest report_month first, which is exactly the gotcha of Appendix D.'
AS
SELECT d.account_id, d.product_risks, d.util_month, d.report_month,
       d.cor_orig_predict AS cor_total_predict_lt,
       d.bal_orig_predict AS bal_total_predict_lt,
       12 AS lifetime_cutoff_statement
FROM RISK_DM.DM.NPV_GEN5_DETAILS d
WHERE d.statement_num = 12 AND d.cor_orig_predict IS NOT NULL;


---------------------------------------------------------------------------
-- 5.8 DM.ETL_LOG — журнал прогонов.
-- Здесь живёт контракт свежести из Appendix B: PORTFOLIO_COR идёт T-1 по
-- календарным дням, статементные таблицы — только по рабочим, а STM_CC
-- отстаёт на 5 дней. Проверка в понедельник по календарному ожиданию даст
-- ложную тревогу — в этом и смысл.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.DM.ETL_LOG
COMMENT = 'ETL run journal. The freshness contract of Appendix B lives here: PORTFOLIO_COR runs T-1 on calendar days, the statement tables run on business days only and STM_CC lags several days behind. A Monday check against a calendar-day expectation will therefore raise a false alarm - which is the point.'
AS
WITH targets AS (
    SELECT 'RISK_DM.DM.PORTFOLIO_COR' AS table_name, 1 AS lag_days, FALSE AS weekday_only UNION ALL
    SELECT 'RISK_DM.DM.PORTFOLIO_BS',  1, FALSE UNION ALL
    SELECT 'RISK_DM.DM.ACCOUNTS',      1, FALSE UNION ALL
    SELECT 'RISK_DM.DM.UTILIZATIONS',  1, FALSE UNION ALL
    SELECT 'RISK_DM.DM.LIMIT_ACTIONS', 1, FALSE UNION ALL
    SELECT 'RISK_DM.DM.STM_COR_CC',    2, TRUE  UNION ALL
    SELECT 'RISK_DM.DM.STM_CC',        5, TRUE  UNION ALL
    SELECT 'RISK_DM.TABLEAU.COR_CHALLENGER', 1, FALSE
)
SELECT t.table_name, d.date_day AS run_date,
       DATEADD(day, -t.lag_days, d.date_day) AS data_date,
       DATEADD(minute, 5 + MOD(ABS(HASH(t.table_name, d.date_day)), 40),
               DATEADD(hour, 2, d.date_day::TIMESTAMP_NTZ)) AS started_at,
       DATEADD(minute, 25 + MOD(ABS(HASH(t.table_name, d.date_day, 'end')), 50),
               DATEADD(hour, 2, d.date_day::TIMESTAMP_NTZ)) AS finished_at,
       IFF(MOD(ABS(HASH(t.table_name, d.date_day, 'st')), 100) < 2, 'FAILED', 'SUCCESS') AS status,
       MOD(ABS(HASH(t.table_name, d.date_day, 'rows')), 500000) + 10000 AS rows_written
FROM targets t
JOIN RISK_GOV.META.DIM_DATE d
  ON d.date_day BETWEEN DATE '2026-01-01' AND DATE '2026-06-30'
 AND (NOT t.weekday_only OR d.is_business_day);


---------------------------------------------------------------------------
-- ПРИЁМКА ФАЗЫ. Все проверки прогнаны, значения фактические:
--
--   Appendix C, join "COR at inflow"                     1476 строк
--   Appendix B, выходные и праздники в stm_cor_cc.end_date   0
--   Appendix C, статементы №1 с ненулевым COR                0
--   Appendix D, снимков прогноза на account x statement      3.00
--   Appendix D, статементов без прогноза                  23.7%
--   Appendix D, событий CLIP в limit_actions               796
--   Appendix F, расхождение даты ODS (UTC) и DM (CDMX)    59.4%
--
-- Три расчёта COR за апрель 2026, продукт CC:
--   Risk Analytics       (стейтмент, Gen3, statement_num >= 2, x12)  14.62%
--   Portfolio Monitoring (день, Gen3, x365)                          11.92%
--   Finance              (день, Gen2, дельта резерва)                11.38%
-- Разброс 3.2 п.п. — из методических решений, не из расхождения моделей.
---------------------------------------------------------------------------
