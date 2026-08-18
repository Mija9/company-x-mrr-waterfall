-- Classifies each account-month's MRR movement vs. the prior month.
-- This is the core business logic behind the revenue waterfall.

with account_monthly as (

    select * from {{ ref('int_account_monthly_mrr') }}

),

with_history as (

    select
        account_id,
        month_date,
        mrr,
        lag(mrr) over (
            partition by account_id order by month_date
        )                                                       as prior_mrr,

        -- Was this account generating any MRR in a *prior* month within the window?
        -- Distinguishes brand-new revenue (New) from revenue coming back (Reactivation).
        coalesce(
            max(case when mrr > 0 then 1 else 0 end) over (
                partition by account_id order by month_date
                rows between unbounded preceding and 1 preceding
            ),
            0
        ) = 1                                                   as had_mrr_in_earlier_month

    from account_monthly

),

classified as (

    select
        account_id,
        month_date,
        coalesce(prior_mrr, 0)                                 as prior_mrr,
        mrr                                                    as current_mrr,
        mrr - coalesce(prior_mrr, 0)                           as mrr_delta,
        had_mrr_in_earlier_month,

        case
            when coalesce(prior_mrr, 0) = 0 and mrr = 0
                then 'no_activity'
            when coalesce(prior_mrr, 0) = 0 and mrr > 0 and not had_mrr_in_earlier_month
                then 'new'
            when coalesce(prior_mrr, 0) = 0 and mrr > 0 and had_mrr_in_earlier_month
                then 'reactivation'
            when coalesce(prior_mrr, 0) > 0 and mrr = 0
                then 'churn'
            when coalesce(prior_mrr, 0) > 0 and mrr > coalesce(prior_mrr, 0)
                then 'expansion'
            when coalesce(prior_mrr, 0) > 0 and mrr < coalesce(prior_mrr, 0)
                then 'contraction'
            else 'retained'
        end                                                     as movement_type

    from with_history

)

select * from classified
