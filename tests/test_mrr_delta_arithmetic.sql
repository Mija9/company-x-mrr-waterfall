-- Business-logic test: at the account-month grain, prior_mrr + mrr_delta
-- must always equal current_mrr. This is what guarantees the monthly
-- aggregation (fct_mrr_waterfall_monthly) reconciles correctly.

select *
from {{ ref('fct_mrr_waterfall') }}
where abs((prior_mrr + mrr_delta) - current_mrr) > 0.01
