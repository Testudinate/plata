# Query Patterns & Pitfalls



## Pitfalls

### Origination vs CLIP Distinction

When working with `dm.limit_actions`, distinguish origination from CLIP events:

```sql
CASE WHEN bs_day <= utilization_date + 100 THEN 'origination'
     ELSE 'clip'
END AS limit_event_type
```

Requires join to `dm.utilizations` on `account_id` to get `utilization_date`.

### Statement-Based Tables are Weekday-Only

Tables using `end_date` — `stm_cc`, `stm_grzd`, `stm_cor_cc`, `clip_statements`, `npv_naive_details` — only contain **business-day dates**. No Saturday/Sunday entries exist. When checking data freshness on Monday or Tuesday, the latest available date will be the previous Friday.

**Note:** for accurate business day counts (including Mexican public holidays), use `ods.ref.HOLIDAYS` instead of assuming Mon–Fri = business days. See `tables_dm.md` → Reference Tables for the full schema and query patterns.

### COR% Calculation

Always filter `statement_num >= 2`. Statement 1 has zero COR (no payment due date has passed), which dilutes the ratio. Annualize with `* 12`, not by day-weighting.

### Product Filter by Schema

| Schema | Filter column | Example |
|--------|--------------|---------|
| `dm.*` | `product_risks` | `WHERE product_risks = 'CC'` |
| `tableau.*` | `account_type` | `WHERE account_type = 'CC'` |

Using the wrong column returns no results silently.

### Inflow vs Collection Decomposition

In `tableau.cor_challenger`, derive inflow vs. collection components from `prev_dlq_days`:
```sql
CASE WHEN prev_dlq_days > 0 THEN cor ELSE 0 END AS cor_collection_fact_derived
```

## Joining Actuals to Gen5v1 Forecast (Statement Level)

The statement-level Tableau dashboard compares actual COR to gen5v1 forecast at statement level. To replicate this in SQL, join `dm.stm_cor_cc` (actuals) to `dm.npv_gen5_details` (forecast) on `account_id` × `statement_num`:

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
    -- Actual COR% (cor_prnp is NEGATIVE, so negate)
    -SUM(a.cor_prnp) / NULLIF(SUM(a.avg_balance_prnp_net), 0) * 12 AS actual_cor_pct,
    -- Forecast COR% (cor_total_predict is POSITIVE)
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

**Tableau formulas** (for reference):
- `cor_fact% = sum(COR_PRNP) / sum(AVG_BALANCE_PRNP_NET) * 12`
- `cor_forecast$ = if STATEMENT_NUM > 1 then -COR_TOTAL_PREDICT else 0 end`
- `cor_forecast% = sum(cor_forecast$) / sum(BAL_TOTAL_PREDICT) * 12`

**Gotchas**:
- Use `QUALIFY ROW_NUMBER()` to deduplicate gen5v1 forecasts — multiple `report_month` snapshots exist per account × statement; take the latest.
- A non-trivial share of statements have no forecast (NULL or 0 `cor_total_predict`). Includes all stmt=1 plus some others. Always filter these out, otherwise unmatched rows inflate actual balance and distort the comparison.
- Sign conventions: `cor_prnp` is negative (cost), `cor_total_predict` is positive (expected loss). Negate one side to align.
- A pre-joined materialization exists in `dds.stm_fact_forecast`, but the join pattern above is preferred for full control over deduplication and filtering.

## Analytical Patterns

### COR% Bridge Decomposition (Numerator vs Denominator)

When COR% deviates from forecast, decompose into:
- **Numerator effect** (worse/better COR abs): `(actual_cor/forecast_bal - forecast_cor/forecast_bal) * 12`
- **Denominator effect** (balance shortfall/excess): `(actual_cor/actual_bal - actual_cor/forecast_bal) * 12`
- **Check**: numerator + denominator = actual_cor_pct - forecast_cor_pct

When actual balance > forecast: denominator effect is negative (reduces COR%). When actual balance < forecast: denominator effect is positive (inflates COR%).

### Forecast Coverage Filter

When joining actuals to gen5v1 forecasts, a non-trivial share of statements have no forecast. Always filter to non-null/non-zero `cor_total_predict` and `bal_total_predict`, otherwise unmatched rows inflate actual balance and distort the comparison.

### T-Statistics for COR Forecast Confidence

When comparing actual COR to gen5v1 forecast, compute a t-statistic for statistical significance:

```sql
-- Delta method for ratio variance estimation
-- cor%_std = cor_forecast% × sqrt(sum(COR_TOTAL_VAR) / power(sum(COR_TOTAL_PREDICT), 2)
--                                  + sum(BAL_TOTAL_VAR) / power(sum(BAL_TOTAL_PREDICT), 2))
-- t = (-cor_fact% + cor_forecast%) / cor%_std
```

`COR_TOTAL_VAR` and `BAL_TOTAL_VAR` columns from `dm.npv_gen5_details`. Uses the delta method for ratio variance estimation. This replicates the confidence band calculation in the statement-level Tableau dashboard.
