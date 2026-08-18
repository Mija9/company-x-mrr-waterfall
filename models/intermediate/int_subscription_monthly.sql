-- Explodes each subscription episode into one row per month in which it was
-- active, so account-level MRR can be aggregated per calendar month.
-- "Active in month M" = started on/before the end of M AND (still open, or
-- ended on/after the start of M).

with subscriptions as (

    select * from {{ ref('stg_subscriptions') }}

),

months as (

    select * from {{ ref('int_month_spine') }}

),

exploded as (

    select
        s.subscription_id,
        s.account_id,
        m.month_date,
        s.plan_tier,
        s.seats,
        s.is_trial,
        s.billing_frequency,
        s.upgrade_flag,
        s.downgrade_flag,
        s.churn_flag,
        s.revenue_mrr_amount as mrr_amount

    from subscriptions s
    cross join months m
    where
        s.start_date <= (m.month_date + interval 1 month - interval 1 day)
        and (s.end_date is null or s.end_date >= m.month_date)

)

select
    subscription_id,
    account_id,
    month_date,
    plan_tier,
    seats,
    is_trial,
    billing_frequency,
    upgrade_flag,
    downgrade_flag,
    churn_flag,
    mrr_amount
from exploded
