-- Grain: one row per month. This is the table the CFO's revenue waterfall
-- report is built on top of. Every column is a standard SaaS MRR movement
-- bucket; beginning_mrr + all movement columns = ending_mrr, and
-- ending_mrr of month M = beginning_mrr of month M+1 (verified by
-- test_mrr_waterfall_reconciles.sql).

with waterfall_detail as (

    select * from {{ ref('fct_mrr_waterfall') }}

),

monthly_movements as (

    select
        month_date,

        sum(case when movement_type = 'new'          then mrr_delta else 0 end) as new_mrr,
        sum(case when movement_type = 'expansion'     then mrr_delta else 0 end) as expansion_mrr,
        sum(case when movement_type = 'contraction'   then mrr_delta else 0 end) as contraction_mrr,
        sum(case when movement_type = 'churn'         then mrr_delta else 0 end) as churned_mrr,
        sum(case when movement_type = 'reactivation'  then mrr_delta else 0 end) as reactivation_mrr,

        count(distinct case when movement_type = 'new'         then account_id end) as new_account_count,
        count(distinct case when movement_type = 'expansion'   then account_id end) as expansion_account_count,
        count(distinct case when movement_type = 'contraction' then account_id end) as contraction_account_count,
        count(distinct case when movement_type = 'churn'       then account_id end) as churned_account_count,
        count(distinct case when movement_type = 'reactivation' then account_id end) as reactivation_account_count,

        count(distinct case when current_mrr > 0 then account_id end) as ending_active_account_count,
        sum(current_mrr) as ending_mrr_check

    from waterfall_detail
    group by 1

)

select
    month_date,

    -- Beginning MRR = prior month's ending MRR (0 for the first month in window).
    coalesce(
        lag(ending_mrr_check) over (order by month_date),
        0
    ) as beginning_mrr,

    new_mrr,
    expansion_mrr,
    contraction_mrr,
    churned_mrr,
    reactivation_mrr,

    new_account_count,
    expansion_account_count,
    contraction_account_count,
    churned_account_count,
    reactivation_account_count,
    ending_active_account_count,

    -- Net new MRR this month, i.e. the sum of every movement bucket.
    (new_mrr + expansion_mrr + contraction_mrr + churned_mrr + reactivation_mrr) as net_new_mrr,

    ending_mrr_check as ending_mrr

from monthly_movements
order by month_date
