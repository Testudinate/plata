---------------------------------------------------------------------------
-- Приёмка фаз 11-14 одним запросом.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE.
--
-- Смысл файла тот же, что у BUILD_ASSERTIONS в фазе 7: состояние стенда
-- должно проверяться запросом, а не пересказом. Пустой список FAIL — это
-- утверждение, которое можно предъявить; «вроде всё работает» — нет.
--
-- Часть проверок числами не выражается (объект существует, alert запущен,
-- индекс поиска обслуживается) — они идут ниже отдельными SHOW.
---------------------------------------------------------------------------

SELECT 'S1 утверждения сборки' AS check_name, COUNT(*)::TEXT AS measured, '0' AS expected,
       IFF(COUNT(*) = 0, 'PASS', 'FAIL') AS verdict
FROM RISK_GOV.DQ.BUILD_ASSERTIONS WHERE NOT passed
UNION ALL SELECT 'S2 карточки таблиц', COUNT(*)::TEXT, '9', IFF(COUNT(*) = 9, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.TABLE_CARDS
UNION ALL SELECT 'S3 грабли с детектором', COUNT(*)::TEXT, '10', IFF(COUNT(*) = 10, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.PITFALLS
UNION ALL SELECT 'S4 золотые вопросы', COUNT(*)::TEXT, '16', IFF(COUNT(*) = 16, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.EVAL_QUESTIONS
UNION ALL SELECT 'S5 чанки для поиска', COUNT(*)::TEXT, '86', IFF(COUNT(*) = 86, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.DOC_CHUNKS
UNION ALL SELECT 'S6 приложения загружены', COUNT(*)::TEXT, '9', IFF(COUNT(*) = 9, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.DOC_RAW
UNION ALL SELECT 'S7 дрейф определения метрики', COUNT(*)::TEXT, '0', IFF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.V_COR_DRIFT WHERE drift_verdict <> 'OK'
UNION ALL SELECT 'S8 dynamic table наполнена', COUNT(*)::TEXT, '45', IFF(COUNT(*) = 45, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.DT_COR_MONTHLY
UNION ALL SELECT 'S9 модель dbt наполнена', COUNT(*)::TEXT, '45', IFF(COUNT(*) = 45, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.COR_CANONICAL_DBT
-- S10 — тот же инвариант, что и singular-тест assert_cor_matches_canon в dbt.
-- Дублирование намеренное: тест ловит на прогоне трансформаций, приёмка — на
-- живом стенде, и падение любого из двух означает разные вещи.
UNION ALL SELECT 'S10 канон = dbt-модель', COUNT(*)::TEXT, '0', IFF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.COR_CANONICAL_DBT d
JOIN RISK_DM.DM.V_COR_CANONICAL c ON c.product_risks = d.product_risks AND c.stmt_month = d.stmt_month
WHERE ABS(d.cor_pct_annual - c.cor_pct_annual) > 0.01
UNION ALL SELECT 'S11 COR за апрель CC', ROUND(MAX(cor_pct_annual), 2)::TEXT, '14.62',
       IFF(ROUND(MAX(cor_pct_annual), 2) = 14.62, 'PASS', 'FAIL')
FROM RISK_DM.DM.V_COR_CANONICAL WHERE product_risks = 'CC' AND stmt_month = DATE '2026-04-01'
-- S12-S14 доказывают, что контур замкнулся снаружи: вопрос дошёл из Telegram,
-- условие сработало в Snowflake и было доставлено ботом обратно.
UNION ALL SELECT 'S12 прогоны агента из Telegram', COUNT(*)::TEXT, '>=1', IFF(COUNT(*) >= 1, 'PASS', 'FAIL')
FROM RISK_GOV.AGENT.AGENT_RUN_LOG WHERE SURFACE = 'telegram'
UNION ALL SELECT 'S13 очередь алертов не пуста', COUNT(*)::TEXT, '>=1', IFF(COUNT(*) >= 1, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.ALERT_LOG
UNION ALL SELECT 'S14 алерты доставлены ботом', COUNT(*)::TEXT, '>=1', IFF(COUNT(*) >= 1, 'PASS', 'FAIL')
FROM RISK_GOV.DQ.ALERT_LOG WHERE DELIVERED_AT IS NOT NULL
ORDER BY 1;


---------------------------------------------------------------------------
-- Проверки состояния объектов. Читать так:
--
--   SHOW AGENTS IN SCHEMA RISK_GOV.AGENT;
--       ожидается RISK_COPILOT
--   SHOW CORTEX SEARCH SERVICES IN SCHEMA RISK_GOV.AGENT;
--       indexing_state = ACTIVE, serving_state = ACTIVE, source_data_num_rows = 86
--   SHOW ALERTS IN SCHEMA RISK_GOV.DQ;
--       state = started (не suspended — иначе детектор создан, но не идёт)
--   SHOW DBT PROJECTS IN SCHEMA RISK_GOV.META;
--       ожидается PLATA_RISK_DBT
--   SHOW DYNAMIC TABLES IN SCHEMA RISK_GOV.DQ;
--       scheduling_state = ACTIVE, target_lag = 1 day
--   SHOW ROLES LIKE 'LLM_AGENT_RO';
--       assigned_to_users = 1 — роль агента имеет носителя. Ноль здесь
--       означает, что граница описана, но ни разу не проверена в бою
--
-- Прогон агента целиком:
--   SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('RISK_GOV.AGENT.RISK_COPILOT',
--     '{"messages":[{"role":"user","content":[{"type":"text",
--       "text":"What was our Cost of Risk for April 2026?"}]}]}');
--   ожидается 14.62% с явным указанием продукта CC
--
-- Прогон dbt:
--   EXECUTE DBT PROJECT RISK_GOV.META.PLATA_RISK_DBT args='build --target sandbox';
--   ожидается PASS=11 ERROR=0
---------------------------------------------------------------------------

-- ЗАМЕР 2026-08-12: 14 из 14 PASS; alert started; поиск ACTIVE/ACTIVE на 86
-- строках; прогонов из Telegram 5; доставленных алертов 1.
