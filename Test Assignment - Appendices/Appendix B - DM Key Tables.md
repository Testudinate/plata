# DM Schema — Table Inventory



## Statement-Level COR Table

### `dm.stm_cor_cc`

Grain: `account_id` x `statement_num`. Statement-level management COR for CC.

- **Filter**: `product_risks = 'CC'`. Dates in `end_date` are **business days only** (weekday-only — no Saturday/Sunday).
- Key columns: `cor_prnp` (Gen3 total, as of current calc date), `cor_prnp_gen2`, `avg_balance_prnp_net`, `dpd1_flg`, `dpd1_balance_prnp`
- Does **not** have inflow/collection COR decomposition — use the challenger table for that.
- Size: large statement-level table.

## Daily COR Table

### `dm.portfolio_cor`

Grain: `account_id` x `report_date`. Daily COR at account level. Multi-billion-row table.

**Filter**: `product_risks` (values: CC, GRZD_CLIPPED, PL, POS, GRZD)

Key columns:

| Column | Type | Description |
|--------|------|-------------|
| `account_id` | TEXT | |
| `report_date` | DATE | |
| `product_risks` | TEXT | Product filter |
| `balance_prnp` | NUMBER | Gross principal balance |
| `balance_net_prnp` | FLOAT | Net principal balance |
| `balance_net_prnp_gen2` | FLOAT | Gen2 net balance |
| `balance_net_prnp_gen3` | FLOAT | Gen3 net balance |
| `credit_limit` | FLOAT | |
| `dlq_first_dt` | DATE | First delinquency date for current episode |
| `dpd` | NUMBER | Days past due |
| `provisions_prnp` | FLOAT | Provision on principal (default gen) |
| `provisions_prnp_gen2` | FLOAT | Gen2 provision stock |
| `provisions_prnp_gen3` | FLOAT | Gen3 provision stock |
| `dlq_balance` | NUMBER | Delinquent balance |
| `current_statement_num` | NUMBER | |
| `statement_id` | TEXT | |
| `risk_beh_type` | TEXT | |

Data freshness: T-1 (calendar days). Available on weekends.

## Daily Balance Sheet Table

### `dm.portfolio_bs`

Grain: `account_id` x `report_date`. Daily balances and provisions.

Similar structure to `portfolio_cor` but additionally includes:
- `balance_net`, `balance_net_yield` — net balance splits
- `provisions`, `provisions_yield` — provision splits including yield
- `beh_type`, `beh_type_detailed` — behavioral segmentation
- `product_risks` — product filter (same values as `portfolio_cor`)

## Key Operational Notes

### Statement-Based Tables are Weekday-Only

Tables using `end_date` as date column — including `stm_cc`, `stm_grzd`, `stm_cor_cc`, `clip_statements`, `npv_naive_details` — only have **business-day dates** (Mon-Fri). This matters for SLA monitoring: expecting weekend dates will always appear as stale. For a Monday/Tuesday check, the latest date will be the previous Friday.

### Vintage Date Convention

Always use `utilization_date` from `dm.accounts` for vintage cohorts. Note: there is no `first_utilization_date` column in this table — if you encounter it in legacy code, it may reference a deprecated column or a different table.

### Data Freshness Summary

| Category | Tables | Expected freshness |
|----------|--------|-------------------|
| Daily (report_date) | portfolio_bs, portfolio_cor, accounts, utilizations, limit_actions | today - 2 (calendar days, including weekends) |
| Statement-based (end_date) | stm_cc, stm_grzd, stm_cor_cc, clip_statements | today - 2, but weekday-only |
| Scoring log | scoring_log | today - 2 |
| NPV models | dm_npv_gen5p_details | Monthly (report_month) |

Pipeline monitoring: `dm.ETL_LOG` tracks ETL runs. `portfolio_cor` is typically T-1. `stm_cc` lags by several days.

## Reference Tables

### `ods.ref.HOLIDAYS` — Mexican Non-Business Day Calendar

Pre-populated calendar of Mexican non-business days (weekends + public holidays). Covers a multi-year window.

**Grain**: one row per non-business day.

| Column | Type | Description |
|--------|------|-------------|
| `KEY` | VARIANT | JSON with internal date serial — ignore, use `DATE` |
| `DATE` | DATE | Calendar date |
| `TYPE` | TEXT | `'WEEKEND'` (Sat/Sun) or `'HOLIDAY'` (Mexican public holiday) |
| `__PROCESSED_DTTM` | TIMESTAMP_NTZ | ETL processing timestamp |
| `__STG_PROCESSED_DTTM` | TIMESTAMP_NTZ | Staging processing timestamp |

**Mexican public holidays included** (TYPE = 'HOLIDAY'): Año Nuevo (Jan 1), Constitución (1st Mon Feb), Natalicio de Benito Juárez (3rd Mon Mar), Semana Santa (Jueves Santo + Viernes Santo, moveable), Día del Trabajo (May 1), Día de las Madres (May 10), Independencia (Sep 16), Revolución (3rd Mon Nov), Inauguración (Dec 1, every 6 years), Día de la Virgen de Guadalupe (Dec 12, bridge days may appear), Navidad (Dec 25), Día de Muertos (Nov 2, observed), plus additional bridge days / asuetos as applicable.

**Use cases**: counting business days in a month for CoR run rate scaling, understanding DPD inflow spikes around holidays (payment due dates shift), statement date and due date calculations, partial-month run rate extrapolation.

**Query pattern — business days in a month:**

```sql
WITH all_days AS (
    SELECT DATEADD(day, seq4(), '2026-01-01') AS dt
    FROM TABLE(GENERATOR(rowcount => 365))
)
SELECT DATE_TRUNC('month', d.dt) AS month_start,
       COUNT(*) AS biz_days
FROM all_days d
LEFT JOIN ods.ref.HOLIDAYS h ON d.dt = h."DATE"
WHERE h."DATE" IS NULL  -- not a holiday or weekend
GROUP BY 1
ORDER BY 1;
```

**Query pattern — holidays only (exclude weekends):**

```sql
SELECT "DATE", TYPE
FROM ods.ref.HOLIDAYS
WHERE TYPE = 'HOLIDAY'
  AND "DATE" BETWEEN '2026-01-01' AND '2026-12-31'
ORDER BY "DATE";
```
