-- Инвариант, на котором стоит обязательный фильтр statement_num >= 2:
-- у первой выписки COR равен нулю, потому что срок платежа ещё не наступал.
-- Если этот тест упадёт, фильтр перестал быть безобидным упрощением, а
-- шаг S1 моста COR сменил знак - см. RISK_GOV.DQ.DRIFT_INVARIANTS.

select
    date_trunc('month', end_date) as stmt_month,
    sum(cor_prnp)                 as cor_on_statement_1
from {{ source('risk_dm', 'stm_cor_cc') }}
where statement_num = 1
group by 1
having abs(sum(cor_prnp)) > 0.01
