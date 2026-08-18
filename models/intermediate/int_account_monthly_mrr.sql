-- Account x month grain. An account can hold multiple concurrently-active
-- subscriptions (see stg_subscriptions docs), so account MRR for a month is
-- the sum of all its active, non-trial subscriptions' MRR that month.

with subscription_monthly as (

    select * from {{ ref('int_subscription_monthly') }}

),

months as (

    select * from {{ ref('int_month_spine') }}

),

accounts as (

    select account_id from {{ ref('stg_accounts') }}

),

-- Every account gets a row for every month in the window, even months
-- with zero active subscriptions, so month-over-month deltas are complete.
account_months as (

    select
        a.account_id,
        m.month_date
    from accounts a
    cross join months m

),

agg as (

    select
        account_id,
        month_date,
        sum(mrr_amount)                                    as mrr,
        count(distinct subscription_id)                    as active_subscription_count,
        sum(case when upgrade_flag then 1 else 0 end)       as upgrade_event_count,
        sum(case when downgrade_flag then 1 else 0 end)     as downgrade_event_count
    from subscription_monthly
    group by 1, 2

)

select
    am.account_id,
    am.month_date,
    coalesce(agg.mrr, 0)                                   as mrr,
    coalesce(agg.active_subscription_count, 0)             as active_subscription_count,
    coalesce(agg.upgrade_event_count, 0)                   as upgrade_event_count,
    coalesce(agg.downgrade_event_count, 0)                 as downgrade_event_count
from account_months am
left join agg
    on am.account_id = agg.account_id
    and am.month_date = agg.month_date
