-- Grain: one row per support ticket, enriched with account context.
-- Included for completeness of the full data model (per the brief); not
-- consumed by the revenue waterfall, but useful context for e.g. correlating
-- support load with churn/contraction.

select
    t.ticket_id,
    t.account_id,
    a.industry,
    a.current_plan_tier,
    t.submitted_at,
    t.closed_at,
    date_trunc('month', t.submitted_at)    as submitted_month,
    t.resolution_time_hours,
    t.priority,
    t.first_response_time_minutes,
    t.satisfaction_score,
    t.escalation_flag,
    t.is_resolved

from {{ ref('stg_support_tickets') }} t
left join {{ ref('dim_accounts') }} a
    on t.account_id = a.account_id
