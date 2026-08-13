{{ config(materialized='view') }}

-- Канонический COR как модель dbt. Формула одна и та же с RISK_DM.DM.V_COR_CANONICAL
-- и с семантической вью SV_COR; тест assert_cor_matches_canon не даёт им разъехаться.
--
-- Обязательный фильтр statement_num >= 2 стоит ВНУТРИ агрегата, а не в WHERE:
-- в WHERE его можно снять запросом сверху, внутри агрегата нельзя. Ровно так же
-- он зашит в SV_COR.
--
-- HAVING найден тестом not_null в первом же прогоне dbt. Две формы фильтра
-- расходятся на краю: WHERE (как в V_COR_CANONICAL) выкидывает месяц целиком,
-- IFF внутри агрегата оставляет строку с нулевым знаменателем и NULL в метрике.
-- Затронуты два месяца - первый месяц жизни каждого продукта, где существуют
-- только первые выписки: CC 2024-07 и GRZD_CLIPPED 2024-08. Строка с NULL хуже
-- отсутствующей: дашборд покажет пустоту, агент может принять её за ноль.
-- Поэтому модель следует канону и месяц с неопределённым COR не выпускает.

with stm as (

    select
        account_id,
        product_risks,
        date_trunc('month', end_date) as stmt_month,
        statement_num,
        cor_prnp,
        avg_balance_prnp_net
    from {{ source('risk_dm', 'stm_cor_cc') }}

)

select
    product_risks,
    stmt_month,
    -sum(iff(statement_num >= 2, cor_prnp, 0))                                    as cor_mxn,
    -sum(iff(statement_num >= 2, cor_prnp, 0))
        / nullif(sum(iff(statement_num >= 2, avg_balance_prnp_net, 0)), 0) * 12 * 100 as cor_pct_annual,
    count(distinct account_id)                                                    as accounts
from stm
group by 1, 2
having sum(iff(statement_num >= 2, avg_balance_prnp_net, 0)) <> 0
