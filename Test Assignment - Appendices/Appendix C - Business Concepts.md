# Business Concepts — Management COR, Signs, Vintages



## Sign Convention (Critical)

Different tables use different signs for COR-related columns. Getting this wrong silently produces incorrect results.

### Negative (cost) — challenger and statement tables

`cor_prnp`, `cor_1p_fact`, `cor_1p_predict`, `cor_collection_fact`, `cor` — all **negative** in:
- `tableau.cor_challenger`
- `dm.stm_cc`, `dm.stm_cor_cc`

### Positive (expected loss) — NPV Gen5 tables

`cor_total_predict`, `bal_total_predict` — **positive** in:
- `dm.npv_gen5_details`, `dm.npv_gen5_agg`

### Deviation Formula

```sql
-- Positive result = better than forecast (actual loss < predicted)
cor_prnp + cor_total_predict AS deviation
```

Signs cancel because `cor_prnp` is negative (actual cost) and `cor_total_predict` is positive (predicted loss).

When joining `stm_cor_cc` to `npv_gen5_details` for fact-vs-forecast comparison, the same sign cancellation applies. The corresponding Tableau dashboard negates `COR_TOTAL_PREDICT` (for stmt > 1) to align forecast with the negative actual sign convention.

### Plotting

When plotting actuals vs. forecast on the same chart, negate the NPV forecast:
```sql
-cor_total_predict AS forecast_cor  -- align with negative actual convention
```
Challenger predictions (`cor_1p_predict`, `cor_collection_predict`) are already negative.

## Management COR Philosophy

In the "ideal" state, **all** management COR comes from two sources only:

1. **Inflow**: accounts migrating from 0 to 1+ DPD
2. **Portfolio growth**: new 0-DPD accounts entering the portfolio

Any nonzero `cor_collection_fact` means collection is underperforming vs. the model's expectation. This is the key diagnostic signal for collection effectiveness.

## Business Plan Provision Conventions (MxGAAP)

The current BP models MxGAAP provisions as **rate × principal balance** only across 13 DPD buckets (30, 60, ..., 390). Key conventions:

1. **Rates apply to principal balance only.** Yield provisions are not part of the BP provision stock. BP captures yield COR as a separate flow item in the economics tabs, not as rate × balance.

2. **To compare fact provisions to BP at DPD-bucket level**, use principal provisions + principal WO only:
   - On-BS: `PROVISIONS` × (`BALANCE_MXGAAP` / `EAD`) from `risk_prov.prov.MXGAAP_PROV_CC` (derives principal provision from total provision and balance ratio)
   - Off-BS: cumulative principal WO (from WO detection query)
   - **Exclude**: yield provisions and yield WO
   - Implied rate = `(prov_prnp + wo_principal) / balance_prnp` — should closely match BP rates.

3. **WO quarter-end mechanics:** BP models write-offs by ramping the provision rate to 100% over the late-stage DPD buckets at quarter ends. In fact data, accounts are then removed from the balance sheet. To reconstruct the "full principal provision stock" comparable to BP, add cumulative principal WO back to on-BS principal provisions.

4. **Product scope:** BP "CC" includes GRZD_CLIPPED. In Snowflake, CC and GRZD_CLIPPED are separate `PRODUCT_RISKS` values. Filter accordingly when reconciling.

## Gen3 COR: Statement Datamart vs Portfolio Snapshot

Two approaches to get Gen3 COR at statement level, capturing different points in time:

1. **Statement datamart** (`stm_cor_cc.cor_prnp`): Gen3 provision for the statement **as of the current calculation date** (today). Continuously updates as the account moves through delinquency. Includes both initial inflow COR and all subsequent collection performance. This is the "COR as of now" view.

2. **Portfolio snapshot** (`portfolio_cor.provisions_prnp_gen3` with `report_date = end_date AND dlq_first_dt = end_date`): Gen3 provision stock **on the exact day the account went 1+ DPD**. Frozen on that date, captures only the initial provision jump, before any collection happens.

**Relationship**: `cor_prnp` (as of now) ≈ `provisions_prnp_gen3` at DPD1 + subsequent collection COR changes. For recently delinquent accounts, these will be close. For older delinquencies, `cor_prnp` will have drifted based on collection performance.

**Tableau pattern**: Use #2 as "COR at inflow" and #1 as "COR as of now". The difference isolates the collection effect. Both are Gen3.

**Join for approach #2**:
```sql
SELECT a.account_id, a.statement_num,
       b.provisions_prnp_gen3 AS cor_at_inflow
FROM risk_dm.dm.stm_cor_cc a
JOIN risk_dm.dm.portfolio_cor b
  ON b.account_id = a.account_id
  AND b.report_date = a.end_date
  AND b.dlq_first_dt = a.end_date
WHERE a.dpd1_flg = 1
```

## Vintage Lifecycle (CC)

Understanding how COR% evolves over a vintage's life:

- **Statement 1**: COR% = 0 (no due date has passed yet — no delinquency possible)
- **Early statements**: COR% grows as the vintage seasons and accounts begin missing payments
- **Mid-life**: CLIP runs activate, increasing absolute COR but often reducing COR% as balances grow
- **Mature vintage**: COR% stabilizes

### COR% Aggregation Gotcha

Always filter `statement_num >= 2` when computing aggregate COR%. Statement 1 has zero COR (no due date yet), which dilutes the ratio and makes the vintage look artificially healthier.

Annualize with `* 12`. Do NOT use day-weighting — the standard convention is monthly annualization.

```sql
-- Correct COR% by vintage
SELECT util_month,
       SUM(cor_prnp) / SUM(avg_balance_prnp_net) * 12 AS cor_pct_annualized
FROM dm.stm_cor_cc
WHERE statement_num >= 2
GROUP BY util_month
```
