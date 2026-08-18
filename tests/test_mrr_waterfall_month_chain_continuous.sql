-- Business-logic test: the waterfall must chain cleanly month to month -
-- one month's ending_mrr is next month's beginning_mrr. A break here would
-- mean the waterfall has a gap or double-counts a movement.

with monthly as (

    select
        month_date,
        ending_mrr,
        lead(beginning_mrr) over (order by month_date) as next_month_beginning_mrr
    from {{ ref('fct_mrr_waterfall_monthly') }}

)

select *
from monthly
where next_month_beginning_mrr is not null
  and abs(ending_mrr - next_month_beginning_mrr) > 0.01
