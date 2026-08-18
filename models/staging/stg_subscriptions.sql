with source as (

    select * from {{ source('raw', 'raw_subscriptions') }}

),

renamed as (

    select
        subscription_id,
        account_id,
        cast(start_date as date)           as start_date,
        cast(end_date as date)             as end_date,
        plan_tier,
        seats,
        cast(mrr_amount as decimal(18,2))  as mrr_amount,
        cast(arr_amount as decimal(18,2))  as arr_amount,
        cast(is_trial as boolean)          as is_trial,
        cast(upgrade_flag as boolean)      as upgrade_flag,
        cast(downgrade_flag as boolean)    as downgrade_flag,
        cast(churn_flag as boolean)        as churn_flag,
        billing_frequency,
        cast(auto_renew_flag as boolean)   as auto_renew_flag,

        -- Trials never contribute revenue; treat separately downstream.
        case when is_trial then 0 else cast(mrr_amount as decimal(18,2)) end as revenue_mrr_amount

    from source

)

select * from renamed
