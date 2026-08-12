# ID Formats and Join Keys


## Primary Identifiers

| ID | Format | Source | Notes |
|----|--------|--------|-------|
| `account_id` | UUID | `ods.pc_kernel.ACCOUNT` | Universal account identifier. Present in nearly all DM tables. |
| `client_id` | UUID | `ods.pc_kernel.ACCOUNT` | One client can have multiple accounts (CC + PL + GRZD). |
| `application_id` | UUID | `dm.applications` | One per credit application. |
| `statement_id` | Integer | `ods.pf_engine.STATEMENTS` | CC billing statement identifier. |
| `statement_num` | Integer | Derived | Sequential statement number per account (1, 2, 3...). |

## Common Join Patterns

**Daily-grain tables** (most DM tables): join on `account_id` + `report_date`.

**Statement-grain tables** (CC-specific): join on `account_id` + `statement_num`.

**Account master enrichment**: join any table to `dm.accounts` on `account_id` to get `product_risks`, `account_state`, origination date, etc.

**Client-level aggregation**: join through `dm.accounts.client_id` to aggregate across a customer's products.

## Cross-Schema Joins

| From | To | Join Key | Use Case |
|------|----|----------|----------|
| `dm.*` | `dm.accounts` | `account_id` | Add product type, account state |
| `dm.*` | `ods.user_mgmt.USER_DATA` | `client_id` | Add demographics (gender, age, state) |
| `dm.applications` | `dm.scoring_log` | `application_id` | Add scoring details |
| `dm.stm_cc` | `ods.pf_engine.STATEMENTS` | `statement_id` | Add raw statement attributes |
| `dm.*` | `ods.pc_tariffs.TARIFFS_ACCOUNTS` | `account_id` | Add pricing/tariff info |

## Gotchas

- `account_id` is UUID format — always quote in SQL (`WHERE account_id = '...'`)
- Some ODS tables use different column names for the same entity (e.g., `id` instead of `account_id`)
- `report_date` is date type (no time component) in DM tables, but timestamps exist in ODS
- When joining DM to ODS, beware timezone differences (DM is Mexico City, ODS may be UTC)

## Additional Join Patterns

### Origination vs CLIP in Limit Actions

To distinguish origination limits from CLIP events, join `dm.limit_actions` to `dm.utilizations` on `account_id`, then apply: `bs_day <= utilization_date + 100` = origination, `> 100` = CLIP.

### Statement-Based Tables are Weekday-Only

Tables using `end_date` as date column (stm_cc, stm_grzd, stm_cor_cc, clip_statements, npv_naive_details) only have business-day dates (Mon-Fri). Expecting weekend dates will always show as stale.

### COR% Aggregation

Always filter `statement_num >= 2` when aggregating COR%. Statement 1 has zero COR (no due date to miss yet), which dilutes the ratio. Annualize with `* 12`, NOT by day-weighting.
