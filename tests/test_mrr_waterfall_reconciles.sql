-- Business-logic test: for every month, beginning_mrr + net_new_mrr must
-- equal ending_mrr, within a cent of rounding tolerance. Returns any
-- offending rows (a passing test returns zero rows).

select
    month_date,
    beginning_mrr,
    net_new_mrr,
    ending_mrr,
    (beginning_mrr + net_new_mrr) as calculated_ending_mrr
from {{ ref('fct_mrr_waterfall_monthly') }}
where abs((beginning_mrr + net_new_mrr) - ending_mrr) > 0.01
