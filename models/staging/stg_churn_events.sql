with source as (

    select * from {{ source('raw', 'raw_churn_events') }}

),

renamed as (

    select
        churn_event_id,
        account_id,
        cast(churn_date as date)                   as churn_date,
        reason_code,
        cast(refund_amount_usd as decimal(18,2))   as refund_amount_usd,
        cast(preceding_upgrade_flag as boolean)    as preceding_upgrade_flag,
        cast(preceding_downgrade_flag as boolean)  as preceding_downgrade_flag,
        cast(is_reactivation as boolean)           as is_reactivation,
        nullif(trim(feedback_text), '')            as feedback_text

    from source

)

select * from renamed
