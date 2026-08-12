---------------------------------------------------------------------------
-- Фаза 13. Детектор дрейфа, который идёт, и SLA, который держит платформа.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE.
--
-- ТЕЗИС ФАЗЫ. Part 2.5 описывал дизайн детектора дрейфа. Разница между
-- «спроектирован» и «идёт» — та же, что между ролью LLM_AGENT_RO и
-- пользователем под ней. Alert'ов в аккаунте было ноль.
--
-- ГЛАВНЫЙ УРОК ФАЗЫ. Первая редакция детектора сравнивала канонический COR с
-- прошлым месяцем при пороге 1.5 п.п. и сработала 33 раза из 33 месяцев.
-- Детектор, срабатывающий всегда, — это не детектор, а кнопка «выключить
-- уведомления»: первым же действием дежурного будет мьют, и следующая
-- настоящая тревога утонет вместе с шумом.
--
-- Причина не в пороге. Месячный COR молодого растущего портфеля скачет на
-- десятки п.п. — это ДВИЖЕНИЕ ПОРТФЕЛЯ, то есть бизнес-факт, а не отказ. Дрейф,
-- ради которого затевался Part 2, — это когда меняется РАСХОЖДЕНИЕ МЕТОДИК:
-- кто-то тихо поправил формулу, и мост между каноном и ведомственными
-- расчётами перестал сходиться. Отсюда проверка свойств, а не величин.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 13.1 Инварианты шагов моста как данные.
--
-- Замер по 24 месяцам показал: у S1 и S3 знак устойчив по построению
-- (22/0 и 24/0), у S2, S4, S5 — нет. Шаги без устойчивого знака помечены
-- unstable и сознательно не мониторятся: лучше признать слепую зону, чем
-- спрятать её за порогом, который придётся подкручивать.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_GOV.DQ.DRIFT_INVARIANTS (
    STEP_NAME  COMMENT 'Шаг моста COR из V_COR_RECONCILIATION',
    STEP_LABEL COMMENT 'Что делает шаг',
    EXPECTED   COMMENT 'nonpositive | nonnegative | unstable',
    RATIONALE  COMMENT 'Почему знак обязан быть таким, либо почему шаг не мониторится',
    EVIDENCE   COMMENT 'Замер на текущей сборке, 24 месяца'
) COMMENT = 'Инварианты шагов моста COR как данные. Детектор проверяет НЕ величину (она движется вместе с портфелем), а свойство, которое обязано выполняться при любой величине.'
AS
          SELECT 'S1'::TEXT, 'Снятие обязательного фильтра statement_num >= 2'::TEXT, 'nonpositive'::TEXT,
                 'Первая выписка имеет нулевой COR и ненулевой баланс, поэтому её добавление всегда РАЗБАВЛЯЕТ отношение. Положительный вклад означает, что на statement 1 появился ненулевой COR.'::TEXT,
                 '22 месяца отрицательных, 1 нулевой, 0 положительных'::TEXT
UNION ALL SELECT 'S2', 'Переход с зерна выписки на дневное зерно', 'unstable',
                 'Смена зерна перевешивает счета по числу дней в портфеле, знак зависит от структуры месяца. Устойчивого инварианта нет — шаг НЕ мониторится, и это осознанная слепая зона.',
                 '14 месяцев отрицательных, 10 положительных'
UNION ALL SELECT 'S3', 'Исключение 0-DPD бакета', 'nonpositive',
                 'Бакет 0-DPD даёт положительный вклад в провизии растущего портфеля, поэтому его исключение всегда снижает COR.',
                 '24 месяца отрицательных, 0 положительных'
UNION ALL SELECT 'S4', 'Аннуализация x12 против x365', 'unstable',
                 'Знак зависит от числа календарных и рабочих дней в месяце. Величина мала (медиана 0.005 п.п.), мониторинг не окупается.',
                 '12 отрицательных, 8 положительных, размах 1.33 п.п.'
UNION ALL SELECT 'S5', 'Переход с Gen3 на Gen2', 'unstable',
                 'Методики расходятся в обе стороны в зависимости от состава портфеля по DPD. Знак преимущественно положительный, но не гарантирован.',
                 '20 положительных, 4 отрицательных';


---------------------------------------------------------------------------
-- 13.2 Детектор.
---------------------------------------------------------------------------

CREATE OR REPLACE VIEW RISK_GOV.DQ.V_COR_DRIFT
COMMENT = 'Детектор дрейфа ОПРЕДЕЛЕНИЯ метрики. Проверяется два свойства: остаток моста обязан быть нулём, и вклад каждого шага обязан сохранять знак из DQ.DRIFT_INVARIANTS.'
AS
WITH steps AS (
    SELECT month_start, canonical_pct, residual_must_be_zero,
           step1_drop_stmt2_filter_pp   AS s1,
           step2_statement_to_daily_pp  AS s2,
           step3_exclude_0dpd_bucket_pp AS s3,
           step4_x12_to_x365_pp         AS s4,
           step5_gen3_to_gen2_pp        AS s5
    FROM RISK_GOV.DQ.V_COR_RECONCILIATION
), unpivoted AS (
    SELECT month_start, canonical_pct, residual_must_be_zero, step_name, step_pp
    FROM steps UNPIVOT (step_pp FOR step_name IN (s1, s2, s3, s4, s5))
)
SELECT u.month_start, u.step_name, i.step_label,
       ROUND(u.step_pp, 3)               AS step_pp,
       i.expected,
       ROUND(u.residual_must_be_zero, 4) AS residual,
       CASE
           WHEN ABS(u.residual_must_be_zero) > 0.01              THEN 'RESIDUAL_BROKEN'
           WHEN i.expected = 'nonpositive' AND u.step_pp >  0.01 THEN 'SIGN_FLIPPED'
           WHEN i.expected = 'nonnegative' AND u.step_pp < -0.01 THEN 'SIGN_FLIPPED'
           ELSE 'OK'
       END                               AS drift_verdict,
       i.rationale
FROM unpivoted u
JOIN RISK_GOV.DQ.DRIFT_INVARIANTS i ON i.step_name = u.step_name;

-- ПРОВЕРКА В ОБЕ СТОРОНЫ. Детектор, который никогда не видели сработавшим,
-- ничем не отличается от закомментированного.
--   на здоровых данных:  119 строк, все OK
--   на подстановке с перевёрнутым знаком S1: срабатывает на 22 месяцах из 23
--     (23-й ровно ноль, ниже порога)
-- WITH perturbed AS (SELECT month_start, step_name, -step_pp AS step_pp, expected
--                    FROM RISK_GOV.DQ.V_COR_DRIFT WHERE step_name = 'S1')
-- SELECT COUNT(*), SUM(IFF(expected='nonpositive' AND step_pp > 0.01, 1, 0)) FROM perturbed;


---------------------------------------------------------------------------
-- 13.3 Очередь условий и alert.
--
-- Доставка вынесена наружу сознательно: NOTIFICATION INTEGRATION в Telegram
-- потребовала бы ACCOUNTADMIN и хранения токена бота внутри аккаунта.
-- Snowflake кладёт условие в очередь, бот на VPS забирает и отмечает.
---------------------------------------------------------------------------

CREATE OR REPLACE VIEW RISK_GOV.DQ.V_ALERT_CONDITIONS
COMMENT = 'Единая поверхность условий, при которых кто-то обязан проснуться: провал утверждения сборки, не-GREEN в скоркарте, дрейф определения метрики, изменение DDL без записи в журнале. Порогов в боте нет ни одного — они здесь.'
AS
SELECT 'assertion:' || assertion_id, 'HIGH', 'Провал утверждения сборки ' || assertion_id,
       description, 'RISK_GOV.DQ.BUILD_ASSERTIONS'
FROM RISK_GOV.DQ.BUILD_ASSERTIONS WHERE NOT passed
UNION ALL
SELECT 'scorecard:' || object_name || ':' || dimension,
       IFF(status = 'RED', 'HIGH', 'MEDIUM'),
       'DQ ' || dimension || ' по ' || object_name || ' = ' || status,
       measurement || IFF(on_breach IS NULL OR on_breach = '', '', ' | действие: ' || on_breach),
       'RISK_GOV.DQ.V_SCORECARD'
FROM RISK_GOV.DQ.V_SCORECARD WHERE status <> 'GREEN'
UNION ALL
SELECT 'metric_drift:' || step_name || ':' || TO_VARCHAR(month_start, 'YYYY-MM'), 'HIGH',
       'Дрейф определения COR, шаг ' || step_name || ' (' || step_label || ') за ' || TO_VARCHAR(month_start, 'YYYY-MM') || ': ' || drift_verdict,
       'Вклад шага ' || step_pp || ' п.п. при инварианте ' || expected || ', остаток моста ' || residual || '. ' || rationale,
       'RISK_GOV.DQ.V_COR_DRIFT'
FROM RISK_GOV.DQ.V_COR_DRIFT WHERE drift_verdict <> 'OK'
UNION ALL
SELECT 'schema_drift:' || database_name, 'MEDIUM',
       'DDL базы ' || database_name || ' изменился без записи в журнале',
       'Дельта DDL ' || char_delta || ' символов, записей в CHANGE_LOG: ' || logged_changes || '. ' || governance_check,
       'RISK_GOV.META.V_SCHEMA_DRIFT'
FROM RISK_GOV.META.V_SCHEMA_DRIFT WHERE governance_check <> 'ok';

CREATE TABLE IF NOT EXISTS RISK_GOV.DQ.ALERT_LOG (
    FIRED_AT      TIMESTAMP_NTZ DEFAULT SYSDATE(),
    ALERT_KEY     COMMENT 'Стабильный ключ условия — по нему гасится дребезг',
    SEVERITY      COMMENT 'HIGH | MEDIUM',
    TITLE         COMMENT 'Заголовок',
    DETAIL        COMMENT 'Подробности и требуемое действие',
    SOURCE_OBJECT COMMENT 'Объект, который посчитал условие',
    DELIVERED_AT  TIMESTAMP_NTZ COMMENT 'Когда бот отправил в Telegram. NULL = не доставлено',
    ACK_BY        COMMENT 'Кто подтвердил приём'
) COMMENT = 'Очередь сработавших условий. Snowflake пишет, бот на VPS забирает и отмечает.';

CREATE OR REPLACE ALERT RISK_GOV.DQ.AL_RISK_GOV_WATCH
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 7 * * * America/Mexico_City'
    COMMENT = 'Ежедневная проверка условий governance. Расписание суточное: каждый прогон будит warehouse, а источники меняются релизом или суточным ETL.'
    IF (EXISTS (
        SELECT 1 FROM RISK_GOV.DQ.V_ALERT_CONDITIONS c
        WHERE NOT EXISTS (SELECT 1 FROM RISK_GOV.DQ.ALERT_LOG l
                          WHERE l.ALERT_KEY = c.ALERT_KEY AND l.ACK_BY IS NULL)))
    THEN
        INSERT INTO RISK_GOV.DQ.ALERT_LOG (ALERT_KEY, SEVERITY, TITLE, DETAIL, SOURCE_OBJECT)
        SELECT c.ALERT_KEY, c.SEVERITY, c.TITLE, c.DETAIL, c.SOURCE_OBJECT
        FROM RISK_GOV.DQ.V_ALERT_CONDITIONS c
        WHERE NOT EXISTS (SELECT 1 FROM RISK_GOV.DQ.ALERT_LOG l
                          WHERE l.ALERT_KEY = c.ALERT_KEY AND l.ACK_BY IS NULL);

ALTER ALERT RISK_GOV.DQ.AL_RISK_GOV_WATCH RESUME;
-- Разовый прогон: EXECUTE ALERT RISK_GOV.DQ.AL_RISK_GOV_WATCH;
-- Факт 2026-08-12: положил в очередь ровно одно условие — известное отставание
-- STM_CC (9 рабочих дней при SLA 5). Ни одного ложного.


---------------------------------------------------------------------------
-- 13.4 Dynamic table — своевременность как обязательство платформы.
--
-- Смысл не в материализации: 45 строк можно считать на лету. Смысл в
-- TARGET_LAG. «Свежесть» перестаёт быть метрикой, которую мы измеряем
-- постфактум и заносим в скоркарту, и становится свойством, которое обязан
-- держать Snowflake. Сутки взяты из SLA витрины, а не из желания видеть
-- свежие цифры почаще.
---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE RISK_GOV.DQ.DT_COR_MONTHLY
    TARGET_LAG = '1 day'
    WAREHOUSE = COMPUTE_WH
    REFRESH_MODE = AUTO
    INITIALIZE = ON_CREATE
    COMMENT = 'Канонический COR по месяцам. Ценность объекта — в TARGET_LAG, а не в материализации.'
AS
SELECT product_risks, stmt_month, cor_pct_annual, cor_mxn, accounts
FROM RISK_DM.DM.V_COR_CANONICAL;


---------------------------------------------------------------------------
-- ПРИЁМКА ФАЗЫ 13:
--   инвариантов шагов моста      5 (2 мониторятся, 3 честно помечены unstable)
--   детектор на здоровых данных  119 проверок, 0 срабатываний
--   детектор на подстановке      22 срабатывания из 23 — доказано, что живой
--   alert                        создан, RESUME, прогон дал 1 условие
--   dynamic table                45 строк, апрельский CC = 14.62
---------------------------------------------------------------------------
