---------------------------------------------------------------------------
-- Фаза 4. Генератор портфеля — ядро песочницы.
--
-- КТО ЗАПУСКАЕТ: рабочая сессия под ролью HERMES_MCP_ROLE, вручную не нужно.
--
-- Всё, что дальше (фазы 5–6), — проекции одного панельного набора «счёт × день».
-- Порядок стейтментов = порядок зависимостей, менять нельзя.
--
-- ДЕТЕРМИНИЗМ. Ни одного RANDOM(). Псевдослучайность — MOD(ABS(HASH(ключ,
-- соль)), N). Пересборка обязана давать побайтово те же данные: иначе цифры
-- в отчёте разъедутся с цифрами в базе, а песочница ровно для того и нужна,
-- чтобы они совпадали.
--
-- ГДЕ ЖИВЁТ. Схема RISK_DM.RAW, префикс SYNTH_ — это строительные леса,
-- а не данные из приложений. Витрины DM и TABLEAU строятся из них в фазах 5–6.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- 4.1 SYNTH_ACCOUNTS — вселенная счетов. Корень всего.
--
-- 4800 счетов: 3000 CC, 600 GRZD_CLIPPED, 800 PL, 400 POS.
-- Винтажи смещены к недавним месяцам (степень < 1): портфель растёт, поэтому
-- зрелые и молодые когорты сосуществуют — без этого вся вкладка про винтажи
-- из Appendix C была бы вырожденной.
-- Факт: 4800 счетов, 3000 клиентов, 1.6 счёта на клиента (агрегация на уровне
-- клиента из Appendix F осмысленна), 1235 счетов с CLIP, 166 в заморозке.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_ACCOUNTS
COMMENT = 'Synthetic account universe - the root of the sandbox. Every ODS and DM object derives from this table, so ODS and DM never disagree. Fully deterministic: seeded from HASH(seq), no RANDOM() anywhere, a rebuild reproduces byte-identical data.'
AS
WITH spine AS (
    SELECT SEQ4() AS i FROM TABLE(GENERATOR(ROWCOUNT => 4800))
),
typed AS (
    SELECT i,
           CASE WHEN i < 3000 THEN 'CC'
                WHEN i < 3600 THEN 'GRZD_CLIPPED'
                WHEN i < 4400 THEN 'PL'
                ELSE 'POS' END AS product_risks,
           MOD(ABS(HASH(i, 'vintage')),  1000) / 1000.0 AS u_vintage,
           MOD(ABS(HASH(i, 'behavior')), 100)            AS u_beh,
           MOD(ABS(HASH(i, 'limit')),    13)             AS u_limit,
           MOD(ABS(HASH(i, 'stmtday')),  28)             AS u_stmt_day,
           MOD(ABS(HASH(i, 'clip')),     100)            AS u_clip,
           MOD(ABS(HASH(i, 'util')),     100)            AS u_util
    FROM spine
)
SELECT
    i AS account_seq,
    -- UUID собирается из MD5, а не UUID_STRING(): нужен детерминизм.
    LOWER(CONCAT_WS('-',
        SUBSTR(MD5(CONCAT('plata-account-', i)),  1, 8),
        SUBSTR(MD5(CONCAT('plata-account-', i)),  9, 4),
        SUBSTR(MD5(CONCAT('plata-account-', i)), 13, 4),
        SUBSTR(MD5(CONCAT('plata-account-', i)), 17, 4),
        SUBSTR(MD5(CONCAT('plata-account-', i)), 21, 12))) AS account_id,
    -- Не-CC счета переиспользуют клиента из CC-пула: часть клиентов держит
    -- несколько продуктов, как и сказано в Appendix F.
    LOWER(CONCAT_WS('-',
        SUBSTR(MD5(CONCAT('plata-client-', IFF(product_risks = 'CC', i, MOD(i * 7, 3000)))),  1, 8),
        SUBSTR(MD5(CONCAT('plata-client-', IFF(product_risks = 'CC', i, MOD(i * 7, 3000)))),  9, 4),
        SUBSTR(MD5(CONCAT('plata-client-', IFF(product_risks = 'CC', i, MOD(i * 7, 3000)))), 13, 4),
        SUBSTR(MD5(CONCAT('plata-client-', IFF(product_risks = 'CC', i, MOD(i * 7, 3000)))), 17, 4),
        SUBSTR(MD5(CONCAT('plata-client-', IFF(product_risks = 'CC', i, MOD(i * 7, 3000)))), 21, 12))) AS client_id,
    product_risks,
    DATEADD(day, FLOOR(700 * POWER(u_vintage, 0.7)), DATE '2024-07-01') AS utilization_date,
    CASE WHEN u_beh < 40 THEN 'transactor'
         WHEN u_beh < 85 THEN 'revolver'
         ELSE 'delinquent_prone' END AS risk_beh_type,
    CASE product_risks
         WHEN 'CC'           THEN 10000 + 4000 * u_limit
         WHEN 'GRZD_CLIPPED' THEN 20000 + 5000 * u_limit
         WHEN 'PL'           THEN 30000 + 8000 * u_limit
         ELSE                      5000 + 1500 * u_limit
    END::NUMBER(18,2) AS credit_limit_orig,
    1 + u_stmt_day AS statement_day,
    (u_clip < 35 AND product_risks IN ('CC', 'GRZD_CLIPPED')) AS gets_clip,
    -- Замороженная контрольная когорта для tableau.clip_cor_vintage (Appendix H).
    (u_clip < 5  AND product_risks IN ('CC', 'GRZD_CLIPPED')) AS is_clip_freeze,
    CASE WHEN u_beh < 40 THEN 0.05 + u_util / 1000.0
         WHEN u_beh < 85 THEN 0.35 + u_util / 250.0
         ELSE                  0.55 + u_util / 300.0
    END AS target_utilization
FROM typed;


---------------------------------------------------------------------------
-- 4.2 SYNTH_BIZDAY_MAP — последний рабочий день не позже данной даты.
-- Механизм, которым END_DATE выталкивается с выходных и праздников. Именно он,
-- а не фильтр в запросе, делает stm_*-таблицы weekday-only.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_BIZDAY_MAP
COMMENT = 'For any calendar date: the last Mexican business day on or before it. Used to push statement cut dates off weekends and holidays, which is what makes stm_* tables weekday-only (Appendix B, D).'
AS
SELECT date_day,
       is_business_day,
       LAST_VALUE(IFF(is_business_day, date_day, NULL)) IGNORE NULLS OVER (
           ORDER BY date_day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_biz_day
FROM RISK_GOV.META.DIM_DATE;


---------------------------------------------------------------------------
-- 4.3 SYNTH_STATEMENTS — циклы выписок.
-- Факт: 46 625 статементов на 4723 счетах (77 счетов слишком молоды, чтобы
-- получить хоть одну выписку к 30.06.2026), ноль выходных и праздников
-- в END_DATE.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_STATEMENTS
COMMENT = 'Statement cycles per account. END_DATE is always a business day (pushed back off weekends and Mexican holidays) - this is the mechanism behind the weekday-only rule of Appendix B/D. Grain: account x statement_num.'
AS
WITH anchors AS (
    SELECT a.account_seq, a.account_id, a.product_risks, a.utilization_date, a.statement_day,
           CASE WHEN DATE_FROM_PARTS(YEAR(DATEADD(day, 20, a.utilization_date)),
                                     MONTH(DATEADD(day, 20, a.utilization_date)),
                                     a.statement_day) >= DATEADD(day, 20, a.utilization_date)
                THEN DATE_FROM_PARTS(YEAR(DATEADD(day, 20, a.utilization_date)),
                                     MONTH(DATEADD(day, 20, a.utilization_date)),
                                     a.statement_day)
                ELSE DATEADD(month, 1,
                     DATE_FROM_PARTS(YEAR(DATEADD(day, 20, a.utilization_date)),
                                     MONTH(DATEADD(day, 20, a.utilization_date)),
                                     a.statement_day))
           END AS first_stmt_raw
    FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
),
seq AS (
    SELECT SEQ4() + 1 AS statement_num FROM TABLE(GENERATOR(ROWCOUNT => 26))
),
raw_cycles AS (
    SELECT an.account_seq, an.account_id, an.product_risks, an.utilization_date,
           s.statement_num,
           DATEADD(month, s.statement_num - 1, an.first_stmt_raw) AS end_raw
    FROM anchors an
    CROSS JOIN seq s
    WHERE DATEADD(month, s.statement_num - 1, an.first_stmt_raw) <= DATE '2026-06-30'
)
SELECT c.account_seq, c.account_id, c.product_risks, c.utilization_date, c.statement_num,
       bm.prev_biz_day                         AS end_date,
       bmd.prev_biz_day                        AS due_date,
       DATE_TRUNC('month', c.utilization_date) AS util_month
FROM raw_cycles c
JOIN RISK_DM.RAW.SYNTH_BIZDAY_MAP bm  ON bm.date_day  = c.end_raw
JOIN RISK_DM.RAW.SYNTH_BIZDAY_MAP bmd ON bmd.date_day = DATEADD(day, 20, c.end_raw);


---------------------------------------------------------------------------
-- 4.4 SYNTH_QUARTER_END — даты списания (последний рабочий день квартала).
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_QUARTER_END
COMMENT = 'Last business day of each quarter - the write-off date. WO happens quarterly (Dec/Mar/Jun/Sep) per Appendix E.'
AS
SELECT DATE_TRUNC('quarter', date_day) AS quarter_start,
       MAX(IFF(is_business_day, date_day, NULL)) AS wo_date
FROM RISK_GOV.META.DIM_DATE
GROUP BY 1;


---------------------------------------------------------------------------
-- 4.5 SYNTH_EPISODES — эпизоды просрочки.
--
-- ПОЧЕМУ ЭПИЗОДЫ, А НЕ МАРКОВСКАЯ ЦЕПЬ ПО ДНЯМ. Цепь по определению
-- последовательна: состояние дня зависит от вчерашнего. В SQL это либо
-- рекурсивный CTE (медленно на 1.5 млн строк), либо процедурный цикл. Эпизод
-- даёт ту же наблюдаемую структуру — dlq_first_dt, рост DPD, излечение,
-- списание — оставаясь декларативным. Эпизоды разложены по непересекающимся
-- сегментам последовательности выписок, поэтому наложиться не могут
-- по построению, а не по проверке.
--
-- Факт: 2545 эпизодов на 1799 счетах (37% портфеля когда-либо просрочен),
-- 262 списания (10% эпизодов), средняя длительность 44 дня.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_EPISODES
COMMENT = 'Delinquency episodes: at most 3 per account, placed in disjoint segments of the statement sequence so they can never overlap by construction. Modelling episodes rather than a day-by-day Markov chain keeps the generator declarative (no recursion) while producing the same observable structure: dlq_first_dt, DPD roll-forward, cure and write-off.'
AS
WITH acc AS (
    SELECT a.account_seq, a.account_id, a.risk_beh_type, MAX(s.statement_num) AS n_stmts
    FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
    JOIN RISK_DM.RAW.SYNTH_STATEMENTS s ON s.account_seq = a.account_seq
    GROUP BY 1, 2, 3
),
sized AS (
    SELECT acc.*,
           CASE risk_beh_type
                WHEN 'transactor' THEN IFF(MOD(ABS(HASH(account_seq, 'nepisodes')), 100) < 85, 0, 1)
                WHEN 'revolver'   THEN CASE WHEN MOD(ABS(HASH(account_seq, 'nepisodes')), 100) < 60 THEN 0
                                            WHEN MOD(ABS(HASH(account_seq, 'nepisodes')), 100) < 90 THEN 1
                                            ELSE 2 END
                ELSE                   CASE WHEN MOD(ABS(HASH(account_seq, 'nepisodes')), 100) < 40 THEN 1
                                            WHEN MOD(ABS(HASH(account_seq, 'nepisodes')), 100) < 75 THEN 2
                                            ELSE 3 END
           END AS n_episodes
    FROM acc
    WHERE n_stmts >= 2
),
-- Отдельный CTE, а не WHERE в предыдущем: иначе выражение seg_len вычисляется
-- до фильтра и делит на ноль у счетов без эпизодов.
active AS (
    SELECT * FROM sized WHERE n_episodes >= 1
),
eps AS (
    SELECT a.*, e.episode_num,
           GREATEST(1, FLOOR((a.n_stmts - 1) / a.n_episodes)) AS seg_len
    FROM active a
    JOIN (SELECT SEQ4() + 1 AS episode_num FROM TABLE(GENERATOR(ROWCOUNT => 3))) e
      ON e.episode_num <= a.n_episodes
),
placed AS (
    SELECT eps.*,
           LEAST(n_stmts, 2 + (episode_num - 1) * seg_len
                            + MOD(ABS(HASH(account_seq, episode_num, 'slot')), seg_len)) AS hit_statement_num,
           MOD(ABS(HASH(account_seq, episode_num, 'severity')), 100) AS u_sev
    FROM eps
),
with_dates AS (
    SELECT p.account_seq, p.account_id, p.risk_beh_type, p.episode_num, p.hit_statement_num, p.u_sev,
           DATEADD(day, 1, st.due_date) AS episode_start,
           -- 60% гасятся до 30 dpd, 20% до 60, 10% до 90, 10% уходят в списание.
           CASE WHEN p.u_sev < 60 THEN  5 + MOD(ABS(HASH(p.account_seq, p.episode_num, 'dur')), 26)
                WHEN p.u_sev < 80 THEN 31 + MOD(ABS(HASH(p.account_seq, p.episode_num, 'dur')), 30)
                WHEN p.u_sev < 90 THEN 61 + MOD(ABS(HASH(p.account_seq, p.episode_num, 'dur')), 30)
                ELSE NULL END AS cure_duration_days,
           (p.u_sev >= 90) AS is_wo
    FROM placed p
    JOIN RISK_DM.RAW.SYNTH_STATEMENTS st
      ON st.account_seq = p.account_seq AND st.statement_num = p.hit_statement_num
)
SELECT w.account_seq, w.account_id, w.episode_num, w.hit_statement_num, w.episode_start, w.is_wo,
       CASE WHEN w.is_wo THEN COALESCE(
               IFF(qe.wo_date >= DATEADD(day, 120, w.episode_start), qe.wo_date, qe2.wo_date), qe2.wo_date)
       END AS wo_date,
       CASE WHEN w.is_wo
            THEN DATEDIFF('day', w.episode_start,
                     COALESCE(IFF(qe.wo_date >= DATEADD(day, 120, w.episode_start), qe.wo_date, qe2.wo_date), qe2.wo_date)) + 1
            ELSE w.cure_duration_days
       END AS duration_days
FROM with_dates w
LEFT JOIN RISK_DM.RAW.SYNTH_QUARTER_END qe
       ON qe.quarter_start = DATE_TRUNC('quarter', DATEADD(day, 120, w.episode_start))
LEFT JOIN RISK_DM.RAW.SYNTH_QUARTER_END qe2
       ON qe2.quarter_start = DATEADD(month, 3, DATE_TRUNC('quarter', DATEADD(day, 120, w.episode_start)));


---------------------------------------------------------------------------
-- 4.6 SYNTH_PANEL — дневная панель «счёт × день». Физическое ядро.
--
-- Ставки резерва по бакетам DPD расходятся между Gen2 и Gen3 в ранних бакетах:
-- hazard-модель Gen3 резервирует свежую просрочку агрессивнее, чем LGD-модель
-- Gen2. Расхождение намеренно НЕБОЛЬШОЕ: Appendix G прямо говорит, что
-- помесячные результаты Gen2 «очень близки к Gen3».
--
-- Факт: 1 505 516 строк, 4800 счетов, 4.92% дней в просрочке,
-- покрытие резервами 3.14% (Gen3) и 3.06% (Gen2).
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_PANEL
COMMENT = 'Daily account-day panel: the physical core of the sandbox. Every DM and TABLEAU table is a projection of this. Balance ramps over the first statements, CLIP raises the limit after day 150+ (so the origination-vs-CLIP rule of Appendix D holds), DPD comes from SYNTH_EPISODES, and two provision streams (Gen2, Gen3) run in parallel on the same balance - that parallel pair is what makes the three COR definitions disagree.'
AS
WITH acc_end AS (
    SELECT a.*,
           COALESCE((SELECT MIN(e.wo_date) FROM RISK_DM.RAW.SYNTH_EPISODES e
                     WHERE e.account_seq = a.account_seq AND e.is_wo), DATE '2026-06-30') AS last_day,
           -- CLIP строго позже 150-го дня: правило Appendix D
           -- (bs_day <= utilization_date + 100 = origination) должно работать.
           DATEADD(day, 150 + MOD(ABS(HASH(a.account_seq, 'clipday')), 90), a.utilization_date) AS clip_date
    FROM RISK_DM.RAW.SYNTH_ACCOUNTS a
),
spine AS (
    SELECT SEQ4() AS d FROM TABLE(GENERATOR(ROWCOUNT => 730))
),
panel AS (
    SELECT a.account_seq, a.account_id, a.product_risks, a.risk_beh_type,
           a.utilization_date, a.credit_limit_orig, a.target_utilization,
           a.gets_clip, a.is_clip_freeze, a.clip_date,
           DATEADD(day, s.d, a.utilization_date) AS report_date
    FROM acc_end a
    JOIN spine s ON DATEADD(day, s.d, a.utilization_date) <= LEAST(a.last_day, DATE '2026-06-30')
    WHERE a.utilization_date <= DATE '2026-06-30'
),
with_stmt AS (
    SELECT p.*, st.statement_num AS current_statement_num
    FROM panel p
    ASOF JOIN RISK_DM.RAW.SYNTH_STATEMENTS st
        MATCH_CONDITION (p.report_date >= st.end_date)
        ON p.account_seq = st.account_seq
),
with_dlq AS (
    SELECT w.*, ep.episode_start, ep.duration_days, ep.is_wo,
           IFF(w.report_date < DATEADD(day, ep.duration_days, ep.episode_start),
               DATEDIFF('day', ep.episode_start, w.report_date) + 1, 0) AS dpd_raw,
           IFF(w.report_date < DATEADD(day, ep.duration_days, ep.episode_start), ep.episode_start, NULL) AS dlq_first_dt
    FROM with_stmt w
    ASOF JOIN RISK_DM.RAW.SYNTH_EPISODES ep
        MATCH_CONDITION (w.report_date >= ep.episode_start)
        ON w.account_seq = ep.account_seq
),
balanced AS (
    SELECT wd.*,
           credit_limit_orig * IFF(gets_clip AND report_date >= clip_date, 1.4, 1.0) AS credit_limit,
           LEAST(1.0, GREATEST(0.15, DATEDIFF('day', utilization_date, report_date) / 150.0)) AS ramp,
           1.0 + 0.07 * SIN(2 * 3.14159265 * DAYOFYEAR(report_date) / 365.0)
               + IFF(MONTH(report_date) = 12, 0.06, 0.0) AS season,
           0.92 + MOD(ABS(HASH(account_seq, DATE_TRUNC('month', report_date), 'bal')), 17) / 100.0 AS idio
    FROM with_dlq wd
),
final AS (
    SELECT account_seq, account_id, report_date, product_risks, risk_beh_type,
           utilization_date, is_clip_freeze, clip_date, gets_clip,
           COALESCE(current_statement_num, 0) AS current_statement_num,
           COALESCE(dpd_raw, 0) AS dpd,
           dlq_first_dt,
           ROUND(credit_limit, 2) AS credit_limit,
           ROUND(credit_limit * target_utilization * ramp * season * idio, 2) AS balance_prnp
    FROM balanced
)
SELECT f.*,
       ROUND(f.balance_prnp * CASE WHEN f.dpd = 0    THEN 0.008
                                   WHEN f.dpd <= 30  THEN 0.10
                                   WHEN f.dpd <= 60  THEN 0.34
                                   WHEN f.dpd <= 90  THEN 0.60
                                   WHEN f.dpd <= 120 THEN 0.83
                                   ELSE 1.00 END, 2) AS provisions_prnp_gen2,
       ROUND(f.balance_prnp * CASE WHEN f.dpd = 0    THEN 0.006
                                   WHEN f.dpd <= 30  THEN 0.13
                                   WHEN f.dpd <= 60  THEN 0.38
                                   WHEN f.dpd <= 90  THEN 0.62
                                   WHEN f.dpd <= 120 THEN 0.86
                                   ELSE 1.00 END, 2) AS provisions_prnp_gen3,
       IFF(f.dpd > 0, f.balance_prnp, 0) AS dlq_balance
FROM final f;


---------------------------------------------------------------------------
-- 4.7 SYNTH_PANEL_COR — дневной COR как дельта резерва.
--
-- Аддитивность Appendix H выполняется ТОЖДЕСТВЕННО, а не подгонкой:
-- cor = cor_1p_fact + cor_collection_fact по построению. Замер после сборки:
-- ошибка аддитивности ровно 0 и по Gen3, и по Gen2.
--
-- Первый день счёта даёт COR от роста портфеля (LAG с дефолтом 0) — это второй
-- из двух источников «идеального» COR по Appendix C.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_PANEL_COR
COMMENT = 'Daily COR as the negative change in provision stock, decomposed exactly the way Appendix H requires. Gen3: cor = cor_1p_fact + cor_collection_fact holds as an identity, not as a calibration. Gen2: cor_total = cor_dlq_fact + cor_0_bucket. Day one of an account produces COR from portfolio growth, which is the second of the two ideal-state sources named in Appendix C.'
AS
WITH lagged AS (
    SELECT p.*,
           LAG(p.dpd, 1, 0) OVER (PARTITION BY p.account_seq ORDER BY p.report_date) AS prev_dlq_days,
           LAG(p.provisions_prnp_gen2, 1, 0) OVER (PARTITION BY p.account_seq ORDER BY p.report_date) AS prev_prov_gen2,
           LAG(p.provisions_prnp_gen3, 1, 0) OVER (PARTITION BY p.account_seq ORDER BY p.report_date) AS prev_prov_gen3
    FROM RISK_DM.RAW.SYNTH_PANEL p
),
delta AS (
    SELECT l.*,
           -(l.provisions_prnp_gen2 - l.prev_prov_gen2) AS d_gen2,
           -(l.provisions_prnp_gen3 - l.prev_prov_gen3) AS d_gen3
    FROM lagged l
)
SELECT account_seq, account_id, report_date, product_risks, risk_beh_type,
       utilization_date, is_clip_freeze, current_statement_num,
       dpd AS dlq_days, prev_dlq_days, dlq_first_dt,
       credit_limit, balance_prnp, dlq_balance,
       provisions_prnp_gen2, provisions_prnp_gen3,
       ROUND(balance_prnp - provisions_prnp_gen2, 2) AS balance_net_prnp_gen2,
       ROUND(balance_prnp - provisions_prnp_gen3, 2) AS balance_net_prnp_gen3,

       -- Gen3: cor = cor_1p_fact + cor_collection_fact
       ROUND(IFF(prev_dlq_days = 0 AND dlq_days = 0, d_gen3, 0), 2)  AS cor_0_bucket,
       ROUND(IFF(prev_dlq_days = 0 AND dlq_days >= 1, d_gen3, 0), 2) AS cor_1p_fact,
       ROUND(IFF(prev_dlq_days >= 1, d_gen3, 0), 2)                  AS cor_collection_fact,
       ROUND(IFF(prev_dlq_days = 0 AND dlq_days >= 1, d_gen3, 0)
           + IFF(prev_dlq_days >= 1, d_gen3, 0), 2)                  AS cor,

       -- Gen2: cor_total = cor_dlq_fact + cor_0_bucket
       ROUND(IFF(prev_dlq_days = 0 AND dlq_days = 0, d_gen2, 0), 2)  AS cor_0_bucket_gen2,
       ROUND(IFF(prev_dlq_days >= 1 OR dlq_days >= 1, d_gen2, 0), 2) AS cor_dlq_fact,
       ROUND(d_gen2, 2)                                              AS cor_total,

       -- Инфлоу модель предсказывает неплохо, коллекшн — хуже: в «идеальном»
       -- состоянии Appendix C коллекшн-COR равен нулю, а отклонение и есть
       -- сигнал о недоработке взыскания.
       ROUND(IFF(prev_dlq_days = 0 AND dlq_days >= 1, d_gen3, 0)
             * (0.90 + MOD(ABS(HASH(account_seq, report_date, 'p1')), 21) / 100.0), 2) AS cor_1p_predict,
       ROUND(IFF(prev_dlq_days >= 1, d_gen3, 0)
             * (0.55 + MOD(ABS(HASH(account_seq, report_date, 'p2')), 21) / 100.0), 2) AS cor_collection_predict
FROM delta;


---------------------------------------------------------------------------
-- 4.8 SYNTH_STM_COR — статементный срез.
-- День относится к тому статементу, чей END_DATE — первый на эту дату или
-- позже. Статемент 1 несёт нулевой COR по построению (срока платежа ещё
-- не было), поэтому фильтр statement_num >= 2 из Appendix C имеет смысл.
---------------------------------------------------------------------------

CREATE OR REPLACE TABLE RISK_DM.RAW.SYNTH_STM_COR
COMMENT = 'Statement-level aggregation of the daily panel. A day belongs to the statement whose END_DATE is the first one on or after it. Statement 1 carries zero COR by construction - no due date has passed yet (Appendix C), which is exactly what makes the statement_num >= 2 filter matter.'
AS
WITH daily_assigned AS (
    SELECT p.*, st.statement_num AS stm_num, st.end_date, st.util_month
    FROM RISK_DM.RAW.SYNTH_PANEL_COR p
    ASOF JOIN RISK_DM.RAW.SYNTH_STATEMENTS st
        MATCH_CONDITION (p.report_date <= st.end_date)
        ON p.account_seq = st.account_seq
),
agg AS (
    SELECT account_seq, account_id, product_risks, utilization_date, util_month,
           stm_num AS statement_num, end_date,
           SUM(cor)                   AS cor_prnp_raw,
           SUM(cor_total)             AS cor_prnp_gen2_raw,
           AVG(balance_net_prnp_gen3) AS avg_balance_prnp_net,
           AVG(balance_prnp)          AS avg_balance_prnp,
           MAX(IFF(prev_dlq_days = 0 AND dlq_days >= 1, 1, 0)) AS dpd1_flg,
           MAX(IFF(prev_dlq_days = 0 AND dlq_days >= 1, balance_prnp, 0)) AS dpd1_balance_prnp,
           MAX(dlq_days)  AS max_dlq_days,
           MIN(dlq_first_dt) AS dlq_first_dt
    FROM daily_assigned
    WHERE stm_num IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7
)
SELECT account_seq, account_id, product_risks, utilization_date, util_month,
       statement_num, end_date,
       ROUND(IFF(statement_num = 1, 0, cor_prnp_raw), 2)      AS cor_prnp,
       ROUND(IFF(statement_num = 1, 0, cor_prnp_gen2_raw), 2) AS cor_prnp_gen2,
       ROUND(avg_balance_prnp_net, 2)                         AS avg_balance_prnp_net,
       ROUND(avg_balance_prnp, 2)                             AS avg_balance_prnp,
       IFF(statement_num = 1, 0, dpd1_flg)                    AS dpd1_flg,
       ROUND(IFF(statement_num = 1, 0, dpd1_balance_prnp), 2) AS dpd1_balance_prnp,
       max_dlq_days, dlq_first_dt
FROM agg;


---------------------------------------------------------------------------
-- ЗАМЕР ПОСЛЕ СБОРКИ. Три расчёта COR за апрель 2026 по CC:
--   Risk Analytics      (стейтмент, Gen3, statement_num >= 2, x12)  10.60%
--   Portfolio Monitoring (день, Gen3, x365)                         11.12%
--   Finance             (день, Gen2, дельта резерва)                11.23%
-- Тот же расчёт Risk Analytics без фильтра statement_num >= 2:      10.45%
--
-- Разложение Gen3 за апрель: инфлоу 13.18%, коллекшн −2.06% (высвобождение
-- при излечении), 0-бакет +0.52%. 13.18 − 2.06 = 11.12 — сходится.
---------------------------------------------------------------------------
