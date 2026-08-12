# TABLEAU Schema — Table Inventory



## COR Challenger Table

### `tableau.cor_challenger`

Grain: `account_id` x `report_date`. Daily COR with Gen3 decomposition. This is the primary table for comparing Gen2 vs Gen3 management provisions at a granular level.

**Critical — filter column**: use `account_type` (NOT `product_risks`). Values: CC, GRZD, PL, POS, GRZD_CLIPPED.

Key columns:

| Column | Description |
|--------|-------------|
| `cor` | Gen3 total management COR |
| `cor_total` | Gen2 total management COR |
| `cor_1p_fact` | Gen3 inflow (0→1+ DPD) actual |
| `cor_1p_predict` | Gen3 inflow predicted |
| `cor_collection_fact` | Gen3 collection actual |
| `cor_collection_predict` | Gen3 collection predicted |
| `net_balance_prnp` | Net principal balance |
| `balance_prnp` | Gross principal balance |
| `dlq_days` | Current DPD |
| `prev_dlq_days` | Previous day's DPD |
| `provisions_dlq_gen3` | Gen3 delinquent provisions |

### Additive Decomposition

- Gen3: `cor = cor_1p_fact + cor_collection_fact`
- Gen2: `cor_total = cor_dlq_fact + cor_0_bucket`

### Inflow vs Collection Decomposition

Derive inflow vs. collection components from `prev_dlq_days`:
```sql
CASE WHEN prev_dlq_days > 0 THEN cor ELSE 0 END AS cor_collection_fact_derived
```

### Gen3 Decomposition via `prev_dlq_days`

Beyond the basic inflow/collection split, Gen3 COR can be decomposed into finer DPD buckets using `prev_dlq_days`. This is useful for bridge decomposition analysis (e.g., monthly COR waterfall charts).

| Component | Filter | Description |
|-----------|--------|-------------|
| DPD0 growth | `cor_0_bucket` | Provision change on performing (0-DPD) portfolio |
| 1+ DPD inflow | `cor WHERE prev_dlq_days = 0 AND dlq_days >= 1` | New delinquencies entering 1+ DPD |
| Collection 1-30 | `cor WHERE prev_dlq_days BETWEEN 1 AND 30` | Early-stage collection |
| Collection 31-90 | `cor WHERE prev_dlq_days BETWEEN 31 AND 90` | Mid-stage collection |
| Collection 90+ | `cor WHERE prev_dlq_days > 90` | Late-stage (typically a release) |

**Verification**: Components sum to Gen3 total (`cor + cor_0_bucket`) with <0.01pp rounding error.

This decomposition avoids the known `cor_collection_fact` data issue and provides a more granular view than the basic `CASE WHEN prev_dlq_days > 0` fix.

### Sign Convention

All COR columns in this table are **negative** (cost). When comparing to NPV forecasts (which are positive), negate one side to align.

## CLIP Incremental COR Marts

Two materialized views for CLIP analysis — can be queried directly without joins.

### `tableau.clip_cor_monthly`

Grain: one row per `report_month`. Contains total portfolio CoR + CLIP incremental CoR + base CoR, absolute MXN and annualized rates, 95% CI bounds, CLIP share of total CoR, n_accounts, balance totals.

### `tableau.clip_cor_vintage`

Grain: one row per `clip_vintage` x `stmt_after_clip` x `is_clip_freeze`. Contains avg incremental CoR, avg incremental balance, annualized incr_cor_pct, cumulative_cor_incr, 95% CI bounds, `vintage_maturity` flag (`'young'` / `'developing'` / `'mature'`).

**Note**: always filter `is_clip_freeze = FALSE` for standard lifecycle curves. See `risk/pilots.md` for the freeze cohort explanation.

