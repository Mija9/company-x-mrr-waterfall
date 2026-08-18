-- Grain: one row per account per month. Included for completeness of the
-- full data model (per the brief); a natural input to a future product
-- engagement / health-score model, not consumed by the revenue waterfall.

with usage as (

    select
        s.account_id,
        date_trunc('month', u.usage_date)  as month_date,
        u.feature_name,
        u.usage_count,
        u.usage_duration_secs,
        u.error_count,
        u.is_beta_feature
    from {{ ref('stg_feature_usage') }} u
    inner join {{ ref('stg_subscriptions') }} s
        on u.subscription_id = s.subscription_id

)

select
    account_id,
    month_date,
    count(distinct feature_name)               as distinct_features_used,
    sum(usage_count)                            as total_usage_events,
    sum(usage_duration_secs)                    as total_usage_duration_secs,
    sum(error_count)                            as total_errors,
    sum(case when is_beta_feature then usage_count else 0 end) as beta_usage_events

from usage
group by 1, 2
