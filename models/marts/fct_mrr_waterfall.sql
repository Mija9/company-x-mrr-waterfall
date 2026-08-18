-- Grain: one row per account per month.
-- This is the drillable detail behind the CFO-facing monthly waterfall
-- (fct_mrr_waterfall_monthly). Every account-month is classified into
-- exactly one movement_type, and mrr_delta always reconciles:
--   prior_mrr + mrr_delta = current_mrr

with changes as (

    select * from {{ ref('int_account_mrr_changes') }}

),

accounts as (

    select
        account_id,
        industry,
        country,
        signup_plan_tier,
        referral_source
    from {{ ref('dim_accounts') }}

),

-- Enrich churn months with the reason code / refund captured on the
-- churn event, when one exists for that account/month.
churn_context as (

    select
        account_id,
        date_trunc('month', churn_date)   as month_date,
        reason_code,
        refund_amount_usd,
        preceding_upgrade_flag,
        preceding_downgrade_flag,
        row_number() over (
            partition by account_id, date_trunc('month', churn_date)
            order by churn_date desc
        ) as rn
    from {{ ref('stg_churn_events') }}

)

select
    c.account_id,
    c.month_date,
    a.industry,
    a.country,
    a.signup_plan_tier,
    a.referral_source,
    c.prior_mrr,
    c.current_mrr,
    c.mrr_delta,
    c.movement_type,
    cc.reason_code                     as churn_reason_code,
    cc.refund_amount_usd               as churn_refund_amount_usd,
    cc.preceding_upgrade_flag          as churn_preceded_by_upgrade,
    cc.preceding_downgrade_flag        as churn_preceded_by_downgrade

from changes c
left join accounts a
    on c.account_id = a.account_id
left join churn_context cc
    on c.account_id = cc.account_id
    and c.month_date = cc.month_date
    and cc.rn = 1
