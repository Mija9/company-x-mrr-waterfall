with accounts as (

    select * from {{ ref('stg_accounts') }}

),

-- One row per account with a snapshot of its most recent subscription info,
-- for easy slicing (current plan, current seats) without re-joining the
-- full subscription history.
latest_subscription as (

    select
        account_id,
        plan_tier          as current_plan_tier,
        seats              as current_seats,
        billing_frequency  as current_billing_frequency,
        row_number() over (
            partition by account_id order by start_date desc
        ) as rn
    from {{ ref('stg_subscriptions') }}

),

churn_summary as (

    select
        account_id,
        count(*)                                   as churn_event_count,
        max(churn_date)                            as most_recent_churn_date,
        sum(refund_amount_usd)                     as total_refunded_usd
    from {{ ref('stg_churn_events') }}
    group by 1

),

support_summary as (

    select
        account_id,
        count(*)                                   as ticket_count,
        sum(case when escalation_flag then 1 else 0 end) as escalated_ticket_count,
        avg(satisfaction_score)                    as avg_satisfaction_score
    from {{ ref('stg_support_tickets') }}
    group by 1

)

select
    a.account_id,
    a.account_name,
    a.industry,
    a.country,
    a.signup_date,
    a.referral_source,
    a.signup_plan_tier,
    a.signup_seats,
    a.is_trial,
    a.has_ever_churned,

    ls.current_plan_tier,
    ls.current_seats,
    ls.current_billing_frequency,

    coalesce(cs.churn_event_count, 0)               as churn_event_count,
    cs.most_recent_churn_date,
    coalesce(cs.total_refunded_usd, 0)              as total_refunded_usd,

    coalesce(ss.ticket_count, 0)                    as ticket_count,
    coalesce(ss.escalated_ticket_count, 0)          as escalated_ticket_count,
    ss.avg_satisfaction_score

from accounts a
left join latest_subscription ls
    on a.account_id = ls.account_id and ls.rn = 1
left join churn_summary cs
    on a.account_id = cs.account_id
left join support_summary ss
    on a.account_id = ss.account_id
