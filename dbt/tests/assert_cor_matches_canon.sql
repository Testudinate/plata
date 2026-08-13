-- Слой трансформаций не имеет права разойтись с каноном.
-- Тест возвращает строки при расхождении больше 0.01 п.п. - в dbt это провал.
-- Именно этот тест превращает "канон описан в реестре" в "канон нельзя обойти,
-- не уронив прогон".

select
    d.product_risks,
    d.stmt_month,
    d.cor_pct_annual  as dbt_pct,
    c.cor_pct_annual  as canonical_pct,
    abs(d.cor_pct_annual - c.cor_pct_annual) as diff_pp
from {{ ref('cor_canonical_dbt') }} d
join RISK_DM.DM.V_COR_CANONICAL c
  on c.product_risks = d.product_risks
 and c.stmt_month    = d.stmt_month
where abs(d.cor_pct_annual - c.cor_pct_annual) > 0.01
