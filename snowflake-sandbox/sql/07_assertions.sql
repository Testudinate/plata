---------------------------------------------------------------------------
-- Фаза 7. Проверочный контур.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
--
-- ЗАЧЕМ. Генератор фазы 4 — сотни строк SQL, и любая правка ставки резерва
-- незаметно ломает аддитивность или знаковое соглашение. Ровно тот класс
-- регресса, про который задание спрашивает в Part 2 («как обнаруживать
-- дрейф»), — начинаем с себя.
--
-- Три ошибки фазы 5 были найдены именно так: не чтением схемы, а прогоном
-- документированных запросов по данным. Этот файл превращает разовые прогоны
-- в постоянный контур.
--
-- КАК ПОЛЬЗОВАТЬСЯ:
--     SELECT * FROM RISK_GOV.DQ.BUILD_ASSERTIONS WHERE NOT passed;
-- Пусто = сборка корректна. Непусто = чинить до того, как строить дальше.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 7.1 COR_BY_DEFINITION — три расчёта одного месяца тремя способами.
--
-- Это доказательная база Part 2: вью не утверждает, что определения
-- расходятся, а показывает НА СКОЛЬКО и какое решение двигает число.
--
-- Главное наблюдение: разрыв НЕ постоянный. В апреле 2026 Risk Analytics
-- выше всех (14.62 против 11.38 у Finance), в марте — ниже всех (3.13
-- против 5.42). Знак расхождения меняется от месяца к месяцу, значит
-- «прибавить два пункта» не работает: нужен один канон, а не поправка.
---------------------------------------------------------------------------

CREATE OR REPLACE VIEW RISK_GOV.DQ.COR_BY_DEFINITION
COMMENT = 'The same month of the same portfolio, computed the three ways the three teams compute it. This view is the evidence base for Part 2: it does not argue that the definitions differ, it shows by how much and which choice moves the number. Change MONTH_START to look at any month.'
AS
WITH months AS (
    SELECT DISTINCT DATE_TRUNC('month', report_date) AS month_start
    FROM RISK_DM.DM.PORTFOLIO_COR
    WHERE report_date >= DATE '2025-09-01'
),
ra AS (
    SELECT DATE_TRUNC('month', end_date) AS month_start,
           -SUM(cor_prnp) / NULLIF(SUM(avg_balance_prnp_net), 0) * 12 * 100 AS cor_pct
    FROM RISK_DM.DM.STM_COR_CC
    WHERE product_risks = 'CC' AND statement_num >= 2
    GROUP BY 1
),
ra_nofilter AS (
    SELECT DATE_TRUNC('month', end_date) AS month_start,
           -SUM(cor_prnp) / NULLIF(SUM(avg_balance_prnp_net), 0) * 12 * 100 AS cor_pct
    FROM RISK_DM.DM.STM_COR_CC
    WHERE product_risks = 'CC'
    GROUP BY 1
),
pm AS (
    SELECT DATE_TRUNC('month', report_date) AS month_start,
           -SUM(cor) / NULLIF(SUM(net_balance_prnp), 0) * 365 * 100 AS cor_pct
    FROM RISK_DM.TABLEAU.COR_CHALLENGER
    WHERE account_type = 'CC'
    GROUP BY 1
),
fin AS (
    SELECT DATE_TRUNC('month', report_date) AS month_start,
           -SUM(cor_total) / NULLIF(SUM(balance_net_prnp_gen2), 0) * 365 * 100 AS cor_pct
    FROM RISK_DM.RAW.SYNTH_PANEL_COR
    WHERE product_risks = 'CC'
    GROUP BY 1
)
SELECT m.month_start,
       ROUND(ra.cor_pct, 2)          AS risk_analytics_pct,
       ROUND(pm.cor_pct, 2)          AS portfolio_monitoring_pct,
       ROUND(fin.cor_pct, 2)         AS finance_pct,
       ROUND(ra_nofilter.cor_pct, 2) AS risk_analytics_without_stmt2_filter_pct,
       ROUND(GREATEST(ra.cor_pct, pm.cor_pct, fin.cor_pct)
           - LEAST(ra.cor_pct, pm.cor_pct, fin.cor_pct), 2) AS spread_pp,
       ROUND(ra.cor_pct - ra_nofilter.cor_pct, 2) AS effect_of_stmt2_filter_pp,
       ROUND(pm.cor_pct - fin.cor_pct, 2)         AS effect_of_generation_pp
FROM months m
JOIN ra          ON ra.month_start          = m.month_start
JOIN ra_nofilter ON ra_nofilter.month_start = m.month_start
JOIN pm          ON pm.month_start          = m.month_start
JOIN fin         ON fin.month_start         = m.month_start;


---------------------------------------------------------------------------
-- 7.2 BUILD_ASSERTIONS_STRUCTURAL — структурные проверки S1..S12 и паттерны
-- запросов из приложений. Каждая строка: что проверяем, откуда требование,
-- фактическое значение, ожидание, вердикт.
---------------------------------------------------------------------------

CREATE OR REPLACE VIEW RISK_GOV.DQ.BUILD_ASSERTIONS_STRUCTURAL
COMMENT = 'Build-time assertions for the sandbox: one row per property the appendices require. A rebuild is only correct when every row has PASSED = TRUE.'
AS
SELECT 'S1a' AS assertion_id, 'sign_convention' AS category, 'Appendix C' AS source_doc,
       'stm_cor_cc.cor_prnp is a cost: negative in aggregate' AS description,
       (SELECT ROUND(SUM(cor_prnp)) FROM RISK_DM.DM.STM_COR_CC)::TEXT AS actual_value,
       '< 0' AS expected,
       (SELECT SUM(cor_prnp) FROM RISK_DM.DM.STM_COR_CC) < 0 AS passed
UNION ALL
SELECT 'S1b', 'sign_convention', 'Appendix H',
       'cor_challenger.cor and cor_total are costs: negative in aggregate',
       (SELECT ROUND(SUM(cor + cor_total)) FROM RISK_DM.TABLEAU.COR_CHALLENGER)::TEXT, '< 0',
       (SELECT SUM(cor) < 0 AND SUM(cor_total) < 0 FROM RISK_DM.TABLEAU.COR_CHALLENGER)
UNION ALL
SELECT 'S1c', 'sign_convention', 'Appendix C',
       'npv_gen5_details predictions are expected losses: never negative',
       (SELECT COUNT(*) FROM RISK_DM.DM.NPV_GEN5_DETAILS
        WHERE cor_total_predict < 0 OR bal_total_predict < 0)::TEXT, '= 0',
       (SELECT COUNT(*) = 0 FROM RISK_DM.DM.NPV_GEN5_DETAILS
        WHERE cor_total_predict < 0 OR bal_total_predict < 0)
UNION ALL
SELECT 'S2a', 'product_filter', 'Appendix A',
       'DM filters on PRODUCT_RISKS and it is populated',
       (SELECT COUNT(DISTINCT product_risks) FROM RISK_DM.DM.PORTFOLIO_COR)::TEXT, '>= 4',
       (SELECT COUNT(DISTINCT product_risks) >= 4 FROM RISK_DM.DM.PORTFOLIO_COR)
UNION ALL
SELECT 'S2b', 'product_filter', 'Appendix D',
       'TABLEAU filtered by the DM column name returns zero rows SILENTLY, not an error',
       (SELECT COUNT(*) FROM RISK_DM.TABLEAU.COR_CHALLENGER WHERE product_risks = 'CC')::TEXT, '= 0',
       (SELECT COUNT(*) = 0 FROM RISK_DM.TABLEAU.COR_CHALLENGER WHERE product_risks = 'CC')
UNION ALL
SELECT 'S3a', 'calendar', 'Appendix B',
       'no weekend or holiday dates in any weekday-only table',
       ((SELECT COUNT(*) FROM RISK_DM.DM.STM_COR_CC s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.STM_CC s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.CLIP_STATEMENTS s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.STM_GRZD s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.NPV_NAIVE_DETAILS s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date))::TEXT,
       '= 0',
       ((SELECT COUNT(*) FROM RISK_DM.DM.STM_COR_CC s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.STM_CC s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.CLIP_STATEMENTS s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.STM_GRZD s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)
      + (SELECT COUNT(*) FROM RISK_DM.DM.NPV_NAIVE_DETAILS s JOIN ODS.REF.HOLIDAYS h ON h."DATE" = s.end_date)) = 0
UNION ALL
SELECT 'S3b', 'calendar', 'Appendix B',
       'portfolio_cor DOES have weekend rows - it is a calendar-day table',
       (SELECT COUNT(*) FROM RISK_DM.DM.PORTFOLIO_COR WHERE DAYOFWEEKISO(report_date) IN (6, 7))::TEXT, '> 0',
       (SELECT COUNT(*) > 0 FROM RISK_DM.DM.PORTFOLIO_COR WHERE DAYOFWEEKISO(report_date) IN (6, 7))
UNION ALL
SELECT 'S4', 'statement_lifecycle', 'Appendix C',
       'statement 1 carries zero COR - no due date has passed yet',
       (SELECT COUNT(*) FROM RISK_DM.DM.STM_COR_CC WHERE statement_num = 1 AND cor_prnp != 0)::TEXT, '= 0',
       (SELECT COUNT(*) = 0 FROM RISK_DM.DM.STM_COR_CC WHERE statement_num = 1 AND cor_prnp != 0)
UNION ALL
SELECT 'S6a', 'additivity', 'Appendix H',
       'Gen3: cor = cor_1p_fact + cor_collection_fact',
       (SELECT ROUND(SUM(ABS(cor - cor_1p_fact - cor_collection_fact)), 4)
        FROM RISK_DM.TABLEAU.COR_CHALLENGER)::TEXT, '= 0',
       (SELECT SUM(ABS(cor - cor_1p_fact - cor_collection_fact)) = 0 FROM RISK_DM.TABLEAU.COR_CHALLENGER)
UNION ALL
SELECT 'S6b', 'additivity', 'Appendix H',
       'Gen2: cor_total = cor_dlq_fact + cor_0_bucket_gen2',
       (SELECT ROUND(SUM(ABS(cor_total - cor_dlq_fact - cor_0_bucket_gen2)), 4)
        FROM RISK_DM.RAW.SYNTH_PANEL_COR)::TEXT, '= 0',
       (SELECT SUM(ABS(cor_total - cor_dlq_fact - cor_0_bucket_gen2)) = 0 FROM RISK_DM.RAW.SYNTH_PANEL_COR)
UNION ALL
SELECT 'S6c', 'additivity', 'Appendix H',
       'prev_dlq_days bucket decomposition sums to cor + cor_0_bucket',
       (SELECT ROUND(ABS(SUM(cor_0_bucket)
                       + SUM(IFF(prev_dlq_days = 0 AND dlq_days >= 1, cor, 0))
                       + SUM(IFF(prev_dlq_days BETWEEN 1 AND 30, cor, 0))
                       + SUM(IFF(prev_dlq_days BETWEEN 31 AND 90, cor, 0))
                       + SUM(IFF(prev_dlq_days > 90, cor, 0))
                       - SUM(cor + cor_0_bucket)), 4)
        FROM RISK_DM.TABLEAU.COR_CHALLENGER)::TEXT, '= 0',
       (SELECT ABS(SUM(cor_0_bucket)
                 + SUM(IFF(prev_dlq_days = 0 AND dlq_days >= 1, cor, 0))
                 + SUM(IFF(prev_dlq_days BETWEEN 1 AND 30, cor, 0))
                 + SUM(IFF(prev_dlq_days BETWEEN 31 AND 90, cor, 0))
                 + SUM(IFF(prev_dlq_days > 90, cor, 0))
                 - SUM(cor + cor_0_bucket)) < 0.01
        FROM RISK_DM.TABLEAU.COR_CHALLENGER)
UNION ALL
SELECT 'S7', 'forecast_dedup', 'Appendix D',
       'several report_month snapshots exist per account x statement - QUALIFY is mandatory',
       (SELECT ROUND(COUNT(*) / COUNT(DISTINCT account_id || statement_num), 2)
        FROM RISK_DM.DM.NPV_GEN5_DETAILS)::TEXT, '> 1',
       (SELECT COUNT(*) / COUNT(DISTINCT account_id || statement_num) > 1 FROM RISK_DM.DM.NPV_GEN5_DETAILS)
UNION ALL
SELECT 'S8', 'forecast_coverage', 'Appendix D',
       'a non-trivial share of statements has no forecast at all',
       (SELECT ROUND(SUM(IFF(cor_total_predict IS NULL, 1, 0)) / COUNT(*) * 100, 1)
        FROM RISK_DM.DM.NPV_GEN5_DETAILS WHERE report_month = DATE '2026-06-01')::TEXT, 'between 10 and 40 pct',
       (SELECT SUM(IFF(cor_total_predict IS NULL, 1, 0)) / COUNT(*) BETWEEN 0.10 AND 0.40
        FROM RISK_DM.DM.NPV_GEN5_DETAILS WHERE report_month = DATE '2026-06-01')
UNION ALL
SELECT 'S9', 'model_change', 'Part 3',
       'gen5v1 re-estimation shifted EL LT materially for the 2025 H1 vintages',
       (SELECT ROUND((SUM(IFF(report_month = DATE '2026-06-01', cor_total_predict, 0))
                    / NULLIF(SUM(IFF(report_month = DATE '2026-06-01', bal_total_predict, 0)), 0))
                   / NULLIF(SUM(IFF(report_month = DATE '2026-03-01', cor_total_predict, 0))
                    / NULLIF(SUM(IFF(report_month = DATE '2026-03-01', bal_total_predict, 0)), 0), 0), 3)
        FROM RISK_DM.DM.NPV_GEN5_DETAILS
        WHERE util_month BETWEEN DATE '2025-01-01' AND DATE '2025-06-01')::TEXT, '> 1.20',
       (SELECT (SUM(IFF(report_month = DATE '2026-06-01', cor_total_predict, 0))
              / NULLIF(SUM(IFF(report_month = DATE '2026-06-01', bal_total_predict, 0)), 0))
             / NULLIF(SUM(IFF(report_month = DATE '2026-03-01', cor_total_predict, 0))
              / NULLIF(SUM(IFF(report_month = DATE '2026-03-01', bal_total_predict, 0)), 0), 0) > 1.20
        FROM RISK_DM.DM.NPV_GEN5_DETAILS
        WHERE util_month BETWEEN DATE '2025-01-01' AND DATE '2025-06-01')
UNION ALL
SELECT 'S10', 'deprecation', 'Appendix G',
       'NPV_GEN5_PV_DETAILS was dropped and must not exist',
       (SELECT COUNT(*) FROM RISK_DM.INFORMATION_SCHEMA.TABLES
        WHERE table_name = 'NPV_GEN5_PV_DETAILS')::TEXT, '= 0',
       (SELECT COUNT(*) = 0 FROM RISK_DM.INFORMATION_SCHEMA.TABLES
        WHERE table_name = 'NPV_GEN5_PV_DETAILS')
UNION ALL
SELECT 'S11a', 'ods_divergence', 'Appendix F',
       'ODS.PC_KERNEL.ACCOUNT names the key ID, not ACCOUNT_ID',
       (SELECT LISTAGG(column_name, ',') WITHIN GROUP (ORDER BY column_name)
        FROM ODS.INFORMATION_SCHEMA.COLUMNS
        WHERE table_schema = 'PC_KERNEL' AND table_name = 'ACCOUNT'
          AND column_name IN ('ID', 'ACCOUNT_ID')), 'ID only',
       (SELECT COUNT(*) = 1 FROM ODS.INFORMATION_SCHEMA.COLUMNS
        WHERE table_schema = 'PC_KERNEL' AND table_name = 'ACCOUNT'
          AND column_name IN ('ID', 'ACCOUNT_ID'))
UNION ALL
SELECT 'S11b', 'ods_divergence', 'Appendix F',
       'ODS timestamps are UTC while DM dates are Mexico City - naive casting shifts the day',
       (SELECT ROUND(SUM(IFF(a.utilization_date != o.OPEN_DTTM::DATE, 1, 0)) / COUNT(*) * 100, 1)
        FROM RISK_DM.DM.ACCOUNTS a JOIN ODS.PC_KERNEL."ACCOUNT" o ON o.ID = a.account_id)::TEXT, '> 20 pct',
       (SELECT SUM(IFF(a.utilization_date != o.OPEN_DTTM::DATE, 1, 0)) / COUNT(*) > 0.20
        FROM RISK_DM.DM.ACCOUNTS a JOIN ODS.PC_KERNEL."ACCOUNT" o ON o.ID = a.account_id)
UNION ALL
SELECT 'S12', 'freshness', 'Appendix B',
       'stm_cc lags behind portfolio_cor in the ETL journal',
       (SELECT MAX(IFF(table_name = 'RISK_DM.DM.PORTFOLIO_COR', data_date, NULL))
             - MAX(IFF(table_name = 'RISK_DM.DM.STM_CC', data_date, NULL))
        FROM RISK_DM.DM.ETL_LOG)::TEXT, '>= 2 days',
       (SELECT MAX(IFF(table_name = 'RISK_DM.DM.PORTFOLIO_COR', data_date, NULL))
             - MAX(IFF(table_name = 'RISK_DM.DM.STM_CC', data_date, NULL)) >= 2
        FROM RISK_DM.DM.ETL_LOG)
UNION ALL
SELECT 'P1', 'documented_pattern', 'Appendix C',
       'the COR-at-inflow join (dlq_first_dt = end_date) returns rows',
       (SELECT COUNT(*) FROM RISK_DM.DM.STM_COR_CC a
        JOIN RISK_DM.DM.PORTFOLIO_COR b ON b.account_id = a.account_id
         AND b.report_date = a.end_date AND b.dlq_first_dt = a.end_date
        WHERE a.dpd1_flg = 1)::TEXT, '> 0',
       (SELECT COUNT(*) > 0 FROM RISK_DM.DM.STM_COR_CC a
        JOIN RISK_DM.DM.PORTFOLIO_COR b ON b.account_id = a.account_id
         AND b.report_date = a.end_date AND b.dlq_first_dt = a.end_date
        WHERE a.dpd1_flg = 1)
UNION ALL
SELECT 'P2', 'documented_pattern', 'Appendix G',
       'MxGAAP yield + principal decomposition reconstructs PROVISIONS exactly',
       (SELECT ROUND(SUM(ABS((PROVISIONS / NULLIF(EAD, 0)) * BALANCE_MXGAAP
                           + (PROVISIONS / NULLIF(EAD, 0)) * GINTEREST_BALANCE_MXGAAP_ADJ
                           - PROVISIONS)), 2) FROM RISK_PROV.PROV.MXGAAP_PROV_CC)::TEXT, '= 0',
       (SELECT SUM(ABS((PROVISIONS / NULLIF(EAD, 0)) * BALANCE_MXGAAP
                     + (PROVISIONS / NULLIF(EAD, 0)) * GINTEREST_BALANCE_MXGAAP_ADJ
                     - PROVISIONS)) < 1 FROM RISK_PROV.PROV.MXGAAP_PROV_CC)
UNION ALL
SELECT 'P3', 'documented_pattern', 'Appendix D',
       'origination and CLIP are separable by the bs_day <= utilization_date + 100 rule',
       (SELECT COUNT(*) FROM RISK_DM.DM.LIMIT_ACTIONS la
        JOIN RISK_DM.DM.UTILIZATIONS u ON u.account_id = la.account_id
        WHERE la.bs_day > DATEADD(day, 100, u.utilization_date))::TEXT, '> 0',
       (SELECT COUNT(*) > 0 FROM RISK_DM.DM.LIMIT_ACTIONS la
        JOIN RISK_DM.DM.UTILIZATIONS u ON u.account_id = la.account_id
        WHERE la.bs_day > DATEADD(day, 100, u.utilization_date))
UNION ALL
SELECT 'P4', 'referential_integrity', 'Appendix F',
       'every account in PORTFOLIO_COR exists in DM.ACCOUNTS',
       (SELECT COUNT(*) FROM (SELECT DISTINCT account_id FROM RISK_DM.DM.PORTFOLIO_COR) p
        LEFT JOIN RISK_DM.DM.ACCOUNTS a ON a.account_id = p.account_id
        WHERE a.account_id IS NULL)::TEXT, '= 0',
       (SELECT COUNT(*) = 0 FROM (SELECT DISTINCT account_id FROM RISK_DM.DM.PORTFOLIO_COR) p
        LEFT JOIN RISK_DM.DM.ACCOUNTS a ON a.account_id = p.account_id
        WHERE a.account_id IS NULL);


---------------------------------------------------------------------------
-- 7.3 BUILD_ASSERTIONS — единая точка входа: структурные проверки плюс
-- метрические (S5).
---------------------------------------------------------------------------

CREATE OR REPLACE VIEW RISK_GOV.DQ.BUILD_ASSERTIONS
COMMENT = 'Single entry point for build-time assertions. A rebuild is correct only when every row has PASSED = TRUE: SELECT * FROM RISK_GOV.DQ.BUILD_ASSERTIONS WHERE NOT passed must come back empty. Structural checks live in BUILD_ASSERTIONS_STRUCTURAL, metric-level checks are added here.'
AS
SELECT * FROM RISK_GOV.DQ.BUILD_ASSERTIONS_STRUCTURAL
UNION ALL
SELECT 'S5a', 'metric_divergence', 'Part 2',
       'the three team definitions disagree materially in April 2026',
       (SELECT spread_pp FROM RISK_GOV.DQ.COR_BY_DEFINITION WHERE month_start = DATE '2026-04-01')::TEXT,
       '> 1 pp',
       (SELECT spread_pp > 1 FROM RISK_GOV.DQ.COR_BY_DEFINITION WHERE month_start = DATE '2026-04-01')
UNION ALL
SELECT 'S5b', 'metric_divergence', 'Part 2',
       'the disagreement is not a constant bias - its sign flips between months, so no single correction factor can reconcile the teams',
       (SELECT COUNT(DISTINCT SIGN(risk_analytics_pct - finance_pct))
        FROM RISK_GOV.DQ.COR_BY_DEFINITION)::TEXT,
       '= 2 (both signs occur)',
       (SELECT COUNT(DISTINCT SIGN(risk_analytics_pct - finance_pct)) = 2
        FROM RISK_GOV.DQ.COR_BY_DEFINITION);


---------------------------------------------------------------------------
-- ПРИЁМКА ФАЗЫ 7: 24 проверки, все PASSED = TRUE.
--
-- Разброс трёх расчётов по месяцам (COR_BY_DEFINITION):
--   2026-06   12.92 / 10.25 /  8.56    разброс 4.37 п.п.
--   2026-05    6.54 /  4.99 /  5.67    разброс 1.55
--   2026-04   14.62 / 11.92 / 11.38    разброс 3.24
--   2026-03    3.13 /  5.02 /  5.42    разброс 2.30   <- порядок перевернулся
--   2026-02   13.59 / 12.95 / 13.69    разброс 0.74
--
-- Вклад фильтра statement_num >= 2 стабильно мал (0.05-0.24 п.п.), а вклад
-- поколения модели меняет знак: от +1.69 до -1.37 п.п. То есть спор трёх
-- команд нельзя закрыть поправочным коэффициентом — только каноном.
---------------------------------------------------------------------------
