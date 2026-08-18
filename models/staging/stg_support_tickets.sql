with source as (

    select * from {{ source('raw', 'raw_support_tickets') }}

),

renamed as (

    select
        ticket_id,
        account_id,
        cast(submitted_at as timestamp)        as submitted_at,
        cast(closed_at as timestamp)           as closed_at,
        resolution_time_hours,
        priority,
        first_response_time_minutes,
        satisfaction_score,
        cast(escalation_flag as boolean)       as escalation_flag,
        (closed_at is not null)                as is_resolved

    from source

)

select * from renamed
