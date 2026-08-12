---------------------------------------------------------------------------
-- Фаза 10. Пересборка, снимок DDL и снос.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE (кроме секции
-- сноса баз — она требует ACCOUNTADMIN).
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 10.1 СНИМОК DDL — он же скрипт пересборки.
--
-- ПОЧЕМУ НЕ ФАЙЛ В РЕПОЗИТОРИИ. Скрипт пересборки, который поддерживают
-- руками, расходится с реальностью — а расхождение документации и реальности
-- и есть предмет всего этого задания. Поэтому скрипт ГЕНЕРИРУЕТСЯ из живого
-- аккаунта: 95 КБ DDL по десяти базам, снятые GET_DDL.
--
-- GET_DDL требует КОНСТАНТНЫХ аргументов — подставить имя из колонки нельзя
-- (проверено: «constant arguments expected»). Отсюда процедура с
-- EXECUTE IMMEDIATE, а не вью.
--
-- Второе назначение снимков — детектор дрейфа: изменившийся DDL_HASH это
-- изменение схемы, а сопоставление с CHANGE_LOG показывает изменения,
-- которые НИКТО НЕ ЗАРЕГИСТРИРОВАЛ. Этот зазор и есть практическое
-- определение слабого change management: он измеряется, а не утверждается.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_GOV.META.DDL_SNAPSHOT (
    SNAPSHOT_TS   TIMESTAMP_NTZ COMMENT 'When the snapshot was taken',
    DATABASE_NAME TEXT          COMMENT 'Database captured',
    DDL_TEXT      TEXT          COMMENT 'Full GET_DDL output for the database - this IS the rebuild script, generated from live state rather than hand-maintained',
    CHAR_COUNT    NUMBER        COMMENT 'Size, for a quick eyeball on drift',
    DDL_HASH      TEXT          COMMENT 'MD5 of the DDL. A changed hash is a schema change that nobody announced'
)
COMMENT = 'Schema snapshots: the generated rebuild script, and the input for schema-drift detection.';

CREATE OR REPLACE PROCEDURE RISK_GOV.META.SP_SNAPSHOT_DDL()
RETURNS STRING
LANGUAGE SQL
COMMENT = 'Captures the full DDL of every sandbox database into RISK_GOV.META.DDL_SNAPSHOT. Run it after any structural change.'
AS
DECLARE
    dbs ARRAY := ARRAY_CONSTRUCT('ODS', 'RISK_DM', 'RISK_PROV', 'RISK_LEGACY', 'RISK_RDS',
                                 'CREDIT_PROD', 'COLLECTION_PROD', 'PAYMENTS_PROD', 'POS_PROD', 'RISK_GOV');
    i INT := 0;
    db STRING;
BEGIN
    WHILE (i < ARRAY_SIZE(dbs)) DO
        db := GET(dbs, i)::STRING;
        EXECUTE IMMEDIATE
            'INSERT INTO RISK_GOV.META.DDL_SNAPSHOT (SNAPSHOT_TS, DATABASE_NAME, DDL_TEXT, CHAR_COUNT, DDL_HASH) ' ||
            'SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, ''' || db || ''', ' ||
            'GET_DDL(''DATABASE'', ''' || db || ''', TRUE), ' ||
            'LENGTH(GET_DDL(''DATABASE'', ''' || db || ''', TRUE)), ' ||
            'MD5(GET_DDL(''DATABASE'', ''' || db || ''', TRUE))';
        i := i + 1;
    END WHILE;
    RETURN 'snapshotted ' || ARRAY_SIZE(dbs)::STRING || ' databases';
END;

CALL RISK_GOV.META.SP_SNAPSHOT_DDL();

CREATE OR REPLACE VIEW RISK_GOV.META.V_SCHEMA_DRIFT
COMMENT = 'Compares the two most recent DDL snapshots per database. A changed DDL_HASH is a schema change; cross-referenced against CHANGE_LOG it shows changes that happened WITHOUT being logged.'
AS
WITH ranked AS (
    SELECT database_name, snapshot_ts, char_count, ddl_hash,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY snapshot_ts DESC) AS rn
    FROM RISK_GOV.META.DDL_SNAPSHOT
),
paired AS (
    SELECT c.database_name, c.snapshot_ts AS current_ts, p.snapshot_ts AS previous_ts,
           c.ddl_hash AS current_hash, p.ddl_hash AS previous_hash,
           c.char_count AS current_chars, p.char_count AS previous_chars
    FROM ranked c
    LEFT JOIN ranked p ON p.database_name = c.database_name AND p.rn = 2
    WHERE c.rn = 1
)
SELECT database_name, current_ts, previous_ts, current_chars, previous_chars,
       current_chars - COALESCE(previous_chars, current_chars) AS char_delta,
       CASE WHEN previous_hash IS NULL        THEN 'FIRST_SNAPSHOT'
            WHEN current_hash = previous_hash THEN 'UNCHANGED'
            ELSE 'SCHEMA_CHANGED' END AS drift_status,
       (SELECT COUNT(*) FROM RISK_GOV.META.CHANGE_LOG cl
        WHERE cl.object_name LIKE paired.database_name || '.%'
          AND cl.changed_on >= COALESCE(paired.previous_ts::DATE, DATE '1900-01-01')) AS logged_changes,
       CASE WHEN previous_hash IS NOT NULL AND current_hash != previous_hash
             AND (SELECT COUNT(*) FROM RISK_GOV.META.CHANGE_LOG cl
                  WHERE cl.object_name LIKE paired.database_name || '.%'
                    AND cl.changed_on >= COALESCE(paired.previous_ts::DATE, DATE '1900-01-01')) = 0
            THEN 'UNLOGGED CHANGE - schema moved with no entry in CHANGE_LOG'
            ELSE 'ok' END AS governance_check
FROM paired;


---------------------------------------------------------------------------
-- 10.2 ПОЛУЧИТЬ СКРИПТ ПЕРЕСБОРКИ
--
-- В Snowsight выполнить и скачать результат:
--     SELECT ddl_text FROM RISK_GOV.META.DDL_SNAPSHOT
--     WHERE database_name = 'RISK_DM'
--       AND snapshot_ts = (SELECT MAX(snapshot_ts) FROM RISK_GOV.META.DDL_SNAPSHOT);
--
-- Порядок применения при восстановлении с нуля: сначала фаза 0 (базы, роли,
-- гранты — под ACCOUNTADMIN), затем DDL баз в порядке зависимостей
-- ODS -> RISK_GOV -> RISK_DM -> остальные, затем наполнение фаз 2–6.
-- DDL восстанавливает СТРУКТУРУ; ДАННЫЕ восстанавливаются прогоном
-- скриптов 02–06, потому что генератор детерминирован и даёт те же строки.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 10.3 ПОРЯДОК ПРОГОНА С НУЛЯ
--
--   00_bootstrap_accountadmin.sql   вручную, ACCOUNTADMIN   ~1 мин
--   01_schemas_and_tags.sql         сессия                  секунды
--   02_calendar_and_reference.sql   сессия                  секунды
--   03_ods_structures.sql           сессия                  секунды
--   04_generator.sql                сессия                  ~1 мин   <- критический путь
--   05_dm_marts.sql                 сессия                  ~1 мин
--   06_tableau_prov_skeletons.sql   сессия                  ~30 сек
--   07_assertions.sql               сессия                  секунды
--   08_governance.sql               сессия                  ~30 сек
--   09_agent_context.sql            сессия                  секунды
--   10_rebuild_and_teardown.sql     сессия                  секунды
--
-- ПРИЁМКА ПОСЛЕ ЛЮБОЙ ПЕРЕСБОРКИ — одна строка:
--     SELECT * FROM RISK_GOV.DQ.BUILD_ASSERTIONS WHERE NOT passed;
-- Пусто = сборка корректна.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 10.4 СНОС
--
-- Данные и объекты (под рабочей ролью). Достаточно, чтобы пересобрать
-- с фазы 1, сохранив базы, роли и гранты фазы 0.
---------------------------------------------------------------------------

-- DROP SCHEMA IF EXISTS RISK_DM.RAW CASCADE;
-- DROP SCHEMA IF EXISTS RISK_DM.DM CASCADE;
-- DROP SCHEMA IF EXISTS RISK_DM.TABLEAU CASCADE;
-- DROP SCHEMA IF EXISTS RISK_DM.DDS CASCADE;
-- DROP SCHEMA IF EXISTS RISK_GOV.META CASCADE;
-- DROP SCHEMA IF EXISTS RISK_GOV.DQ CASCADE;
-- DROP SCHEMA IF EXISTS RISK_GOV.AGENT CASCADE;
-- ... и остальные схемы по списку фазы 1.

-- ПОЛНЫЙ снос, включая базы, роли и монитор расходов — секция отката
-- в конце 00_bootstrap_accountadmin.sql, только под ACCOUNTADMIN.

-- Отвязать DMF перед сносом не требуется (уходят вместе с таблицами), но
-- расписание стоит снять, если таблицы остаются:
-- ALTER TABLE RISK_DM.DM.PORTFOLIO_COR UNSET DATA_METRIC_SCHEDULE;
-- ALTER TABLE RISK_DM.DM.STM_COR_CC UNSET DATA_METRIC_SCHEDULE;
-- ALTER TABLE RISK_DM.TABLEAU.COR_CHALLENGER UNSET DATA_METRIC_SCHEDULE;


---------------------------------------------------------------------------
-- ИТОГ ПЕСОЧНИЦЫ (замерено, не оценено):
--
--   объектов           59 таблиц + 15 вью + 1 семантическая вью
--   строк              8 141 114
--   схем / баз         23 / 10
--   хранилище          0.307 ГБ
--   кредитов на сборку 2.67  (примерно 8 USD)
--   запросов сессии    482
--   DDL                95 КБ по десяти базам
--   утверждений        26, все проходят
--
-- Стоимость поддержания: суточные DMF на трёх таблицах плюс авто-suspend
-- за 60 секунд — единицы кредитов в месяц. Монитор RM_SANDBOX остановит
-- warehouse на 20 кредитах. ВНИМАНИЕ: вызовы Cortex тарифицируются
-- отдельно от warehouse и монитором НЕ ловятся.
---------------------------------------------------------------------------
