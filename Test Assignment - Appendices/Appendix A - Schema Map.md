# Database & Schema Map


## Schema Inventory

| Database.Schema | Layer | Description |
|--------|-------|-------------|
| `risk_dm.dm` | **Data Mart** | Aggregated management-level tables — the primary analytical layer |
| `risk_dm.tableau` | **Tableau** | Production tables feeding Tableau dashboards |
| `risk_legacy.dm` | Risk (legacy DM) | PD model outputs (`pd005_by_stages`), cash loan applications. **Note**: different from `risk_dm.dm` |
| `risk_prov.prov` | Risk Reserves (Provisions) | Production MxGAAP provision tables |
| `risk_dm.dds` | Detail Data Store | Cleaned detailed data — technical layer |
| `risk_dm.raw` | Raw / Staging | Raw ingestion tables — technical layer |
| `risk_rds.dds` | Risk RDS Detail Store | Feature-engineered portfolio data (`portfolio_features`) |
| `pos_prod.dds` | POS Detail Store | POS-specific detailed data — technical layer |
| `credit_prod.dbt` | Credit Product (dbt) | dbt-modeled cashflow tables for CC |
| `collection_prod.dbt` | Collection (dbt) | dbt-modeled collection/agency test group tables |
| `payments_prod.dbt` | Payment Processing (dbt) | Processed transaction data (`emart_transactions`) |
| `ods.pf_engine` | ODS – PF Engine | Operational data: statements, account attributes |
| `ods.pf_loans` | ODS – PF Loans | Operational data: tranches |
| `ods.pc_app` | ODS – PC Application | Operational data: transactions (incl. SPEI_IN) |
| `ods.pc_kernel` | ODS – PC Kernel | Account master source (`ACCOUNT`: account_id, client_id, account_state, account_type) |
| `ods.user_mgmt` | ODS – User Management | User demographics (`USER_DATA`: gender, birthday, state) |
| `ods.fx_rates` | ODS – Banxico/CMEX | FX rates: `USDMXN` exchange rate history |
| `ods.pc_tariffs` | ODS – PC Tariffs | Account tariff/pricing assignments (`TARIFFS_ACCOUNTS`) |
| `ods.pf_gl` | ODS – General Ledger | GL journal entry views (`GL_ENTRY_SOURCES`, `GL_SOURCE_ENGINE`). See `finance/gl_tables.md` |

## Usage Guidance

**For analytical queries**: start with `risk_dm.dm` (the Data Mart). This is the primary layer for management reporting, with pre-joined, aggregated tables.

**For dashboard data**: use `risk_dm.tableau` — these tables are specifically structured for Tableau consumption.

**For raw/source data**: use DDS/RAW schemas or ODS tables. See `tables_technical.md` for details.

**For provisions**: MxGAAP in `risk_prov.prov`.

## Notable Schema Details

### Product Filter Difference (Critical)

| Schema | Filter column | CC value |
|--------|--------------|----------|
| `dm.*` tables | `product_risks` | `'CC'` |
| `tableau.*` tables | `account_type` | `'CC'` |

Using the wrong filter column returns no results or wrong data silently.
