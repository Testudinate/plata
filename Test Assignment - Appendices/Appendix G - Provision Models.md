# Risk Models — Management Provisions, Scoring, NPV


## File Map

| File | What's Inside | When to Load |
|------|---------------|--------------|
| *(this file)* | Gen2/Gen3/Gen5 model overview, EL LT formulas, model comparison | Understanding provision model mechanics |

## Management Provision Model Generations

Plata runs multiple generations of management provision models in parallel. All operate on **principal** (not yield).

### Gen2 vs Gen3 Comparison

| Aspect | Gen2 | Gen3 |
|--------|------|------|
| Status | Official / production | Newer-generation model, gaining adoption |
| Use case | Cross-unit KPIs, management reporting | Collection-specific KPIs |
| Methodology family | Loss-given-default style | Hazard / migration style |
| Monthly results | Very close to Gen3 | Better for granular collection analysis |
| COR decomposition | `cor_total = cor_0_bucket + cor_dlq_fact` | `cor = cor_1p_fact + cor_collection_fact` |

**When to use which**: Gen2 for KPIs shared across units (Total CoR portfolio, management reporting). Gen3 for collection-specific KPIs (CoR after 1 DPD, collection vs. forecast).

### COR Philosophy (Management Provisions)

In the "ideal" state, ALL management COR comes from: (1) 0 to 1+ DPD migration (inflow), and (2) 0-DPD portfolio growth. Any nonzero `cor_collection_fact` signals collection is underperforming vs. the model.

## Gen5 (NPV) Model

Account-level net present value model used for profitability analysis and CLIP decisions.

- **Gen5v1** = current production model. Previous: Gen5v0.
- A late-statement cutoff is used as the "long-term" / "lifetime" reference point.
- **NPV Portfolio** = ORIG + ORIG_CLIP. For older vintages: use ORIG gen5 + ORIG_CLIP gen4. For newer vintages: full gen5.

### Production Tables

| Table | Grain | Size | Description |
|-------|-------|------|-------------|
| `dm.NPV_GEN5_DETAILS` | account x statement | Large statement-level prediction table | Statement-level predictions |
| `dm.NPV_GEN5_AGG` | account | Account-level aggregation | Account-level PV aggregation |

### Deprecated: NPV_GEN5_PV_DETAILS

`NPV_GEN5_PV_DETAILS` was **dropped** in a recent refactor. The columns it contained (`active_clients_predict`, `opex_predict`, `funding_predict`, `debt_funding_share`) have been merged into `NPV_GEN5_DETAILS`. Any queries referencing `PV_DETAILS` must be updated to use `DETAILS` instead.

### EL LT (Expected Loss Lifetime) Calculation

Two equivalent formulas for annualized lifetime COR:

From PV_AGG:
```sql
SELECT SUM(cor_total_predict_lt) / SUM(bal_total_predict_lt) * 12 AS el_lt
FROM dm.npv_gen5_agg
WHERE ...
```

From DETAILS at the lifetime cutoff statement:
```sql
SELECT SUM(cor_orig_predict) / SUM(bal_orig_predict) * 12 AS el_lt
FROM dm.npv_gen5_details
WHERE statement_num = <lifetime_cutoff> AND ...
```

Both produce the same result. The `* 12` annualizes the monthly rate.

### Model Recalculation

Gen5v1 has been re-estimated periodically. Recent recalibrations have materially shifted EL LT for some historical vintage cohorts. Be aware of this when comparing historical NPV snapshots.

## Yield Provision Calculation (MxGAAP)

MxGAAP provisions cover total EAD (principal + accrued interest). The yield/principal decomposition at account level:

```
provision_rate = PROVISIONS / EAD
yield_prov = provision_rate × GINTEREST_BALANCE_MXGAAP_ADJ
prnp_prov = provision_rate × BALANCE_MXGAAP
```

Source table: `risk_prov.prov.MXGAAP_PROV_CC`. See `finance/mxgaap_provisions.md` for full table documentation.

Note: this applies to MxGAAP (regulatory) provisions only. Management provisions (Gen2/Gen3) operate on principal only.

## Scoring Pipeline

Application scoring has four stages, captured in `dm.SCORING_LOG`:

1. **Inner Scoring** (`innerscoring_*`): Basic eligibility (age, duplicates, whitelist).
2. **Pre-Application Scoring** (`preapplicationscoring_*`): Bureau pull, basic score.
3. **Application Scoring** (`applicationscoring_*`): Full risk assessment — PD models, fraud scores, policy rules.
4. **Final Scoring** (`finalscoring_*`): Final decision including KYC, limit assignment, income verification.

Key score fields: `pd002`, `pd003`, `pd005`, `pg001` (payment generation), plus external fraud scores.

## To Be Added

- PD calibration process
- LGD and EAD estimation details
- NPV Gen5 discount rates and cashflow components
- Scoring model feature importance
