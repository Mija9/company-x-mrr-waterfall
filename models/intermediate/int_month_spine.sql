{{
  config(materialized='view')
}}

-- One row per calendar month in the reporting window.
select
    cast(month_date as date) as month_date

from (
    select unnest(
        generate_series(
            cast('{{ var("waterfall_start_month") }}' as date),
            cast('{{ var("waterfall_end_month") }}' as date),
            interval 1 month
        )
    ) as month_date
)
