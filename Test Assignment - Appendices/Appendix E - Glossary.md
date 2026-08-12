# Glossary


## Terms

| Term | Meaning | Context |
|------|---------|---------|
| BS | Balance Sheet | `portfolio_bs` — daily balance/provision table |
| BdC | Buro de Credito | Mexican credit bureau (Circulo de Credito) |
| CAR | Capital Adequacy Ratio | Regulatory capital metric, CRO-level KPI |
| CC | Credit Card | Product line (primary) |
| CLIP | Credit Limit Increase Program | Automated limit management |
| COR | Cost of Risk | Provision expense as % of portfolio. Three methodologies exist. |
| CSP | Collection Strategy Platform | Technology platform for collection strategies |
| CUBE | Internal management reporting workbook | Master Excel workbook for management reporting |
| Califica | BDC Trans Union Califica | CNBV-required bureau product for EPRC variables in MxGAAP provisions. |
| DDS | Detail Data Store | Cleaned detailed data layer |
| DM | Data Mart | Primary analytical schema |
| DPD | Days Past Due | Delinquency measure (1 DPD, 30 DPD, 60 DPD, 90+ DPD) |
| EAD | Exposure at Default | Balance at time of default |
| ECL | Expected Credit Loss | IFRS 9 provision methodology |
| EL LT | Expected Loss Lifetime | Annualized lifetime COR prediction from NPV model. Formula: `cor_predict_lt / bal_predict_lt * 12` |
| EPRC | Expected Probability of Recurrent Credit | Key input variable for CNBV provision model, sourced from Califica (current) or internal model (legacy) |
| FvsP | Fact vs Plan | CUBE comparison columns (absolute and %) |
| GRZD | Garantizada | Secured/guaranteed loan product |
| IFRS | International Financial Reporting Standards | International accounting |
| IRM | Integrated Risk Management | Risk team (Group IRM) |
| LGD | Loss Given Default | Recovery rate complement |
| MxGAAP | Mexican GAAP | Local accounting standards |
| NPV | Net Present Value | Account-level profitability model (Gen5) |
| ODS | Operational Data Store | Source system operational data |
| PD | Probability of Default | Scoring model output |
| PL | Personal Loan (Cash Loan) | Product line |
| POS | Point of Sale | Point-of-sale product line |
| SOX | Sarbanes-Oxley | US compliance standard |
| SPEI | Sistema de Pagos Electronicos Interbancarios | Mexican interbank transfer system |
| STM | Statement | `stm_cc` — statement-level CC metrics |
| TDC | Tarjeta de Credito | CC product code in `DATA_FOR_DM_REGULATORY_PROVISIONS` table. Equivalent to `'CC'` in other schemas. |
| TTM | Time to Market | Risk IT delivery metric by complexity bucket |
| TUC | Total Upfront Cost | Per-utilization acquisition cost (4 buckets) |
| WO | Write-Off | Account balance removal after prolonged delinquency. Occurs quarterly (Dec/Mar/Jun/Sep). |
| add_prov | Additional Provisions | CNBV-required provisions for accounts with incomplete credit assessment (no bureau report or no final scoring). Table: `risk_prov.prov.ADD_PROV`. |
