# Паттерны запросов и подводные камни

*Перевод. Оригинал: [../Test Assignment - Appendices/Appendix D - Query Patterns.md](../Test%20Assignment%20-%20Appendices/Appendix%20D%20-%20Query%20Patterns.md)*

## Подводные камни

### Различие origination и CLIP

При работе с `dm.limit_actions` отличайте выдачу (origination) от событий CLIP:

```sql
CASE WHEN bs_day <= utilization_date + 100 THEN 'origination'
     ELSE 'clip'
END AS limit_event_type
```

Требует джойна к `dm.utilizations` по `account_id`, чтобы получить `utilization_date`.

### Таблицы на уровне выписки — только будни

Таблицы, использующие `end_date` — `stm_cc`, `stm_grzd`, `stm_cor_cc`, `clip_statements`, `npv_naive_details` — содержат **только даты рабочих дней**. Записей за субботу и воскресенье не существует. При проверке свежести данных в понедельник или вторник самой свежей доступной датой будет предыдущая пятница.

**Замечание:** для точного подсчёта рабочих дней (с учётом государственных праздников Мексики) используйте `ods.ref.HOLIDAYS`, а не допущение «пн–пт = рабочие дни». Полную схему и паттерны запросов см. в `tables_dm.md` → Справочные таблицы.

### Расчёт COR%

Всегда фильтруйте `statement_num >= 2`. У выписки 1 COR нулевой (ни одна дата платежа ещё не наступила), что размывает отношение. Аннуализируйте через `* 12`, а не взвешиванием по дням.

### Фильтр по продукту в разных схемах

| Схема | Колонка-фильтр | Пример |
|--------|--------------|---------|
| `dm.*` | `product_risks` | `WHERE product_risks = 'CC'` |
| `tableau.*` | `account_type` | `WHERE account_type = 'CC'` |

Использование не той колонки молча возвращает пустой результат.

### Декомпозиция inflow против collection

В `tableau.cor_challenger` компоненты inflow и collection выводятся из `prev_dlq_days`:
```sql
CASE WHEN prev_dlq_days > 0 THEN cor ELSE 0 END AS cor_collection_fact_derived
```

## Джойн факта к прогнозу Gen5v1 (уровень выписки)

Дашборд Tableau уровня выписки сравнивает фактический COR с прогнозом gen5v1 на уровне выписки. Чтобы воспроизвести это в SQL, джойните `dm.stm_cor_cc` (факт) к `dm.npv_gen5_details` (прогноз) по `account_id` × `statement_num`:

```sql
WITH forecast AS (
    SELECT account_id, statement_num,
           cor_total_predict, bal_total_predict
    FROM risk_dm.dm.npv_gen5_details
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY account_id, statement_num
        ORDER BY report_month DESC
    ) = 1
)
SELECT
    DATE_TRUNC('month', a.end_date) AS stmt_month,
    -- Фактический COR% (cor_prnp ОТРИЦАТЕЛЬНЫЙ, поэтому меняем знак)
    -SUM(a.cor_prnp) / NULLIF(SUM(a.avg_balance_prnp_net), 0) * 12 AS actual_cor_pct,
    -- Прогнозный COR% (cor_total_predict ПОЛОЖИТЕЛЬНЫЙ)
    SUM(f.cor_total_predict) / NULLIF(SUM(f.bal_total_predict), 0) * 12 AS forecast_cor_pct
FROM risk_dm.dm.stm_cor_cc a
JOIN forecast f
    ON a.account_id = f.account_id
    AND a.statement_num = f.statement_num
WHERE a.product_risks = 'CC'
  AND a.statement_num >= 2
  AND f.cor_total_predict IS NOT NULL AND f.cor_total_predict != 0
  AND f.bal_total_predict IS NOT NULL AND f.bal_total_predict != 0
GROUP BY 1
ORDER BY 1;
```

**Формулы Tableau** (для справки):
- `cor_fact% = sum(COR_PRNP) / sum(AVG_BALANCE_PRNP_NET) * 12`
- `cor_forecast$ = if STATEMENT_NUM > 1 then -COR_TOTAL_PREDICT else 0 end`
- `cor_forecast% = sum(cor_forecast$) / sum(BAL_TOTAL_PREDICT) * 12`

**Ловушки**:
- Используйте `QUALIFY ROW_NUMBER()` для дедупликации прогнозов gen5v1 — на пару счёт × выписка существует несколько снапшотов `report_month`; берите последний.
- У заметной доли выписок прогноза нет (NULL или 0 в `cor_total_predict`). Сюда попадают все stmt=1 и часть остальных. Всегда отфильтровывайте их, иначе несматченные строки раздувают фактический баланс и искажают сравнение.
- Соглашения о знаках: `cor_prnp` отрицательный (затраты), `cor_total_predict` положительный (ожидаемые потери). Одной стороне нужно поменять знак.
- Заранее сджойненная материализация есть в `dds.stm_fact_forecast`, но предпочтителен паттерн джойна выше — он даёт полный контроль над дедупликацией и фильтрацией.

## Аналитические паттерны

### Bridge-декомпозиция COR% (числитель против знаменателя)

Когда COR% отклоняется от прогноза, раскладывайте отклонение на:
- **Эффект числителя** (COR в абсолюте хуже/лучше): `(actual_cor/forecast_bal - forecast_cor/forecast_bal) * 12`
- **Эффект знаменателя** (недобор/перебор баланса): `(actual_cor/actual_bal - actual_cor/forecast_bal) * 12`
- **Проверка**: числитель + знаменатель = actual_cor_pct - forecast_cor_pct

Когда фактический баланс > прогнозного, эффект знаменателя отрицательный (снижает COR%). Когда фактический баланс < прогнозного, эффект знаменателя положительный (завышает COR%).

### Фильтр покрытия прогнозом

При джойне факта к прогнозам gen5v1 у заметной доли выписок прогноза нет. Всегда фильтруйте по ненулевым и не-NULL `cor_total_predict` и `bal_total_predict`, иначе несматченные строки раздувают фактический баланс и искажают сравнение.

### T-статистика для доверия к прогнозу COR

При сравнении фактического COR с прогнозом gen5v1 считайте t-статистику для оценки статистической значимости:

```sql
-- Дельта-метод для оценки дисперсии отношения
-- cor%_std = cor_forecast% × sqrt(sum(COR_TOTAL_VAR) / power(sum(COR_TOTAL_PREDICT), 2)
--                                  + sum(BAL_TOTAL_VAR) / power(sum(BAL_TOTAL_PREDICT), 2))
-- t = (-cor_fact% + cor_forecast%) / cor%_std
```

Колонки `COR_TOTAL_VAR` и `BAL_TOTAL_VAR` — из `dm.npv_gen5_details`. Используется дельта-метод для оценки дисперсии отношения. Это воспроизводит расчёт доверительного коридора в дашборде Tableau уровня выписки.
