# Схема DM — инвентаризация таблиц

*Перевод. Оригинал: [../Test Assignment - Appendices/Appendix B - DM Key Tables.md](../Test%20Assignment%20-%20Appendices/Appendix%20B%20-%20DM%20Key%20Tables.md)*

## Таблица COR на уровне выписки

### `dm.stm_cor_cc`

Гранулярность: `account_id` x `statement_num`. Управленческий COR на уровне выписки для CC.

- **Фильтр**: `product_risks = 'CC'`. Даты в `end_date` — **только рабочие дни** (будни, без субботы и воскресенья).
- Ключевые колонки: `cor_prnp` (итог по Gen3, на текущую дату расчёта), `cor_prnp_gen2`, `avg_balance_prnp_net`, `dpd1_flg`, `dpd1_balance_prnp`
- **Не содержит** декомпозиции COR на inflow/collection — для этого используйте challenger-таблицу.
- Размер: большая таблица уровня выписки.

## Таблица дневного COR

### `dm.portfolio_cor`

Гранулярность: `account_id` x `report_date`. Дневной COR на уровне счёта. Таблица на миллиарды строк.

**Фильтр**: `product_risks` (значения: CC, GRZD_CLIPPED, PL, POS, GRZD)

Ключевые колонки:

| Колонка | Тип | Описание |
|--------|------|-------------|
| `account_id` | TEXT | |
| `report_date` | DATE | |
| `product_risks` | TEXT | Фильтр по продукту |
| `balance_prnp` | NUMBER | Валовой баланс основного долга |
| `balance_net_prnp` | FLOAT | Чистый баланс основного долга |
| `balance_net_prnp_gen2` | FLOAT | Чистый баланс по Gen2 |
| `balance_net_prnp_gen3` | FLOAT | Чистый баланс по Gen3 |
| `credit_limit` | FLOAT | |
| `dlq_first_dt` | DATE | Дата начала текущего эпизода просрочки |
| `dpd` | NUMBER | Дней просрочки |
| `provisions_prnp` | FLOAT | Резерв на основной долг (поколение по умолчанию) |
| `provisions_prnp_gen2` | FLOAT | Запас резервов по Gen2 |
| `provisions_prnp_gen3` | FLOAT | Запас резервов по Gen3 |
| `dlq_balance` | NUMBER | Просроченный баланс |
| `current_statement_num` | NUMBER | |
| `statement_id` | TEXT | |
| `risk_beh_type` | TEXT | |

Свежесть данных: T-1 (календарные дни). Доступна и в выходные.

## Таблица дневного баланса

### `dm.portfolio_bs`

Гранулярность: `account_id` x `report_date`. Дневные балансы и резервы.

Структура похожа на `portfolio_cor`, но дополнительно содержит:
- `balance_net`, `balance_net_yield` — разбивка чистого баланса
- `provisions`, `provisions_yield` — разбивка резервов, включая проценты (yield)
- `beh_type`, `beh_type_detailed` — поведенческая сегментация
- `product_risks` — фильтр по продукту (значения те же, что в `portfolio_cor`)

## Ключевые операционные заметки

### Таблицы на уровне выписки — только будни

Таблицы, где датой служит `end_date` — в том числе `stm_cc`, `stm_grzd`, `stm_cor_cc`, `clip_statements`, `npv_naive_details` — содержат **только рабочие дни** (пн–пт). Это важно для мониторинга SLA: если ждать выходных дат, данные всегда будут выглядеть устаревшими. При проверке в понедельник или вторник самой свежей датой будет предыдущая пятница.

### Соглашение о дате винтажа

Для винтажных когорт всегда используйте `utilization_date` из `dm.accounts`. Обратите внимание: колонки `first_utilization_date` в этой таблице нет — если она встретилась вам в легаси-коде, это может быть ссылка на устаревшую колонку или на другую таблицу.

### Сводка по свежести данных

| Категория | Таблицы | Ожидаемая свежесть |
|----------|--------|-------------------|
| Дневные (report_date) | portfolio_bs, portfolio_cor, accounts, utilizations, limit_actions | сегодня - 2 (календарные дни, включая выходные) |
| На уровне выписки (end_date) | stm_cc, stm_grzd, stm_cor_cc, clip_statements | сегодня - 2, но только будни |
| Журнал скоринга | scoring_log | сегодня - 2 |
| NPV-модели | dm_npv_gen5p_details | Ежемесячно (report_month) |

Мониторинг пайплайнов: `dm.ETL_LOG` отслеживает прогоны ETL. `portfolio_cor` обычно T-1. `stm_cc` отстаёт на несколько дней.

## Справочные таблицы

### `ods.ref.HOLIDAYS` — календарь нерабочих дней Мексики

Заранее заполненный календарь нерабочих дней Мексики (выходные + государственные праздники). Покрывает окно в несколько лет.

**Гранулярность**: одна строка на один нерабочий день.

| Колонка | Тип | Описание |
|--------|------|-------------|
| `KEY` | VARIANT | JSON с внутренним серийным номером даты — игнорировать, использовать `DATE` |
| `DATE` | DATE | Календарная дата |
| `TYPE` | TEXT | `'WEEKEND'` (сб/вс) или `'HOLIDAY'` (государственный праздник Мексики) |
| `__PROCESSED_DTTM` | TIMESTAMP_NTZ | Таймстамп обработки ETL |
| `__STG_PROCESSED_DTTM` | TIMESTAMP_NTZ | Таймстамп обработки на staging |

**Включённые государственные праздники Мексики** (TYPE = 'HOLIDAY'): Año Nuevo (1 янв), Constitución (1-й пн февраля), Natalicio de Benito Juárez (3-й пн марта), Semana Santa (Jueves Santo + Viernes Santo, плавающие), Día del Trabajo (1 мая), Día de las Madres (10 мая), Independencia (16 сен), Revolución (3-й пн ноября), Inauguración (1 дек, раз в 6 лет), Día de la Virgen de Guadalupe (12 дек, возможны переносные «мостики»), Navidad (25 дек), Día de Muertos (2 ноя, отмечаемый), плюс дополнительные «мостики» / asuetos, где применимо.

**Сценарии использования**: подсчёт рабочих дней в месяце для масштабирования run rate по CoR, объяснение всплесков inflow по DPD вокруг праздников (сдвигаются даты платежей), расчёты дат выписки и дат платежа, экстраполяция run rate по неполному месяцу.

**Паттерн запроса — рабочие дни в месяце:**

```sql
WITH all_days AS (
    SELECT DATEADD(day, seq4(), '2026-01-01') AS dt
    FROM TABLE(GENERATOR(rowcount => 365))
)
SELECT DATE_TRUNC('month', d.dt) AS month_start,
       COUNT(*) AS biz_days
FROM all_days d
LEFT JOIN ods.ref.HOLIDAYS h ON d.dt = h."DATE"
WHERE h."DATE" IS NULL  -- не праздник и не выходной
GROUP BY 1
ORDER BY 1;
```

**Паттерн запроса — только праздники (без выходных):**

```sql
SELECT "DATE", TYPE
FROM ods.ref.HOLIDAYS
WHERE TYPE = 'HOLIDAY'
  AND "DATE" BETWEEN '2026-01-01' AND '2026-12-31'
ORDER BY "DATE";
```
