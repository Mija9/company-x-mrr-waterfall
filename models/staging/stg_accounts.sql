with source as (

    select * from {{ source('raw', 'raw_accounts') }}

),

renamed as (

    select
        account_id,
        account_name,
        industry,
        country,
        cast(signup_date as date)          as signup_date,
        referral_source,
        plan_tier                          as signup_plan_tier,
        seats                              as signup_seats,
        cast(is_trial as boolean)          as is_trial,
        cast(churn_flag as boolean)        as has_ever_churned

    from source

)

select * from renamed
