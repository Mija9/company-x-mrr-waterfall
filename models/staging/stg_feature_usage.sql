with source as (

    select * from {{ source('raw', 'raw_feature_usage') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['usage_id', 'subscription_id', 'usage_date', 'feature_name', 'usage_count']) }} as usage_pk,
        usage_id,
        subscription_id,
        cast(usage_date as date)              as usage_date,
        feature_name,
        usage_count,
        usage_duration_secs,
        error_count,
        cast(is_beta_feature as boolean)      as is_beta_feature

    from source

)

select * from renamed
