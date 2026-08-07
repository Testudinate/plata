# Test Assignment: Risk Data Governance Lead (v2 — DMBoK-framed)

**Company:** Plata — Mexican fintech (neobank + lending)
**Format:** Written deliverables (document or presentation, your choice). Submit in English.

---

## Context

Plata operates a Snowflake-based data warehouse with 20+ schemas across 6 databases, serving ~10 risk analysts, Tableau dashboards, and increasingly — LLM-based analytical agents. The Risk department (Group IRM) owns the analytical layer but depends on a separate DWH engineering team for platform and upstream pipelines.

You are being evaluated for the **Risk Data Governance Lead** role: managing two datamart analysts, owning the risk analytical layer, and being responsible for data quality, lineage, documentation, and AI readiness. Reports to the Head of Integrated Risk Management.

Maturity across DAMA DMBoK disciplines is uneven. Today the most acute pain is in **Data Quality Management** and **Change Management**; the **Data Catalog** is partially in place; **Reference Data Management** is not currently a primary concern. Please connect your proposals to DMBoK disciplines where useful.

**Appendices:** A — Schema Map · B — DM Tables · C — Business Concepts · D — Query Patterns & Pitfalls · E — Glossary · F — ID Formats · G — Provision Models · H — Tableau Tables · I — Current-State Maturity Assessment (radar + ladders).

---

## Part 1 — Data Landscape Review

You've just joined and these appendices are your day-one documentation.

1. What governance risks do you see, and how do they map to DMBoK?
2. How would you stop the existing inconsistencies (naming, sign conventions, etc.) from getting worse?
3. Who should own which data, and what does ownership mean operationally?

---

## Part 2 — Metric Governance & Data Quality

Three teams calculate "Cost of Risk" differently:

| Team | Table | Grain | Generation | Formula | Annualization |
|------|-------|-------|------------|---------|---------------|
| Risk Analytics | `dm.stm_cor_cc` | Statement | Gen3 | `SUM(cor_prnp) / SUM(avg_balance_prnp_net)` | `* 12` |
| Portfolio Monitoring | `tableau.cor_challenger` | Daily | Gen3 | `SUM(cor) / SUM(net_balance_prnp)` | `* 365` |
| Finance | `dm.portfolio_cor` | Daily | Gen2 | Change in `provisions_prnp_gen2` | Monthly aggregation |

The Head of Risk asks: "What is our actual COR for April?"

Tell us what the canonical definition should be, how you'd get the three teams aligned on it, and how you'd detect drift over time. Frame the drift-detection design against the DQM maturity ladder.

---

## Part 3 — Change Management Scenario

The main NPV model (Gen5v1) has just been re-estimated and Expected Loss Lifetime has shifted materially for several vintage cohorts. Three downstream consumers depend on it: Tableau dashboards, monthly management reporting, and an LLM agent answering ad-hoc analyst questions.

How do you manage this change end-to-end? Frame your answer against the Change Management ladder.

---

## Part 4 — AI Readiness

LLM agents will increasingly query the risk DWH autonomously. The appendices are roughly what an agent would have today.

Evaluate them for agent consumption rather than human consumption — what's missing for the agent, and what's missing to lift our **Data Catalog** to a Controlled state? What governance is needed before agents can be trusted with risk data?

---

## Part 5 — Maturity Placement & 90-Day Plan

Using Appendix I:

1. Place Plata on each of the four ladders, citing appendix evidence.
2. Pick the **two** dimensions you'd push first in your first 90 days. Define what "one notch up" looks like concretely.
3. What would you measure in the first 30 days to validate or revise that prioritization — and what's deliberately *not* a 90-day priority?

---

## Submission

Aim for ~5–8 pages or equivalent slides. We value prioritization and clarity over completeness. List any assumptions you make beyond the appendices.
