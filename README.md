# Company X — MRR Revenue Waterfall (dbt project)

A dbt project that turns Company X's raw billing/product/support extracts into
a CFO-ready **monthly MRR revenue waterfall** — the movement of MRR month over
month, broken into New, Expansion, Contraction, Churn, and Reactivation.

Built for the Oxylabs Analytics Engineer technical task (Steps 1–5). Step 6
(presentation) is intentionally out of scope for this repo.

---

## 1. Quickstart

```bash
# 1. Clone and enter the project
git clone <this-repo-url>
cd company_x

# 2. Python env + deps
python3 -m venv .venv && source .venv/bin/activate
pip install dbt-core dbt-duckdb duckdb

# 3. Install dbt packages (dbt_utils)
dbt deps

# 4. Load the 5 CSVs into DuckDB's `raw` schema
#    (simulates the EL step a Fivetran/Airbyte connector would normally do)
python3 load_raw_data.py

# 5. Build everything: run all models + all tests
dbt build --profiles-dir .

# 6. Browse the docs site (lineage graph, column-level docs)
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

No external database needed — everything runs against a local
`company_x.duckdb` file. To point at a different warehouse, add a new target
in `profiles.yml` and swap the adapter (dbt-duckdb → dbt-snowflake / -bigquery
/ -postgres etc.); the SQL is written in portable ANSI SQL + a handful of
DuckDB-specific date functions (`generate_series`, `date_trunc`) that have
direct equivalents on every major warehouse.

**Query the result directly:**
```sql
select * from main_marts.fct_mrr_waterfall_monthly order by month_date;
```

---

## 2. Architecture

```
raw (loaded outside dbt, via load_raw_data.py)
  raw_accounts, raw_subscriptions, raw_feature_usage,
  raw_support_tickets, raw_churn_events
        │
        ▼
staging/            1:1 with source tables. Rename, cast, light cleanup only.
  stg_accounts, stg_subscriptions, stg_feature_usage,
  stg_support_tickets, stg_churn_events
        │
        ▼
intermediate/       Reshaping + business logic, not meant for direct BI use.
  int_month_spine            — calendar spine for the reporting window
  int_subscription_monthly   — subscriptions exploded to (subscription, active month)
  int_account_monthly_mrr    — aggregated to (account, month), zero-filled
  int_account_mrr_changes    — core waterfall classification logic
        │
        ▼
marts/              Business-ready, documented, tested. What analysts query.
  dim_accounts                — one row per account
  fct_mrr_waterfall           — account x month detail (drillable)
  fct_mrr_waterfall_monthly   — the CFO deliverable: one row per month
  fct_support_tickets         — completeness: full ticket detail
  fct_feature_usage_monthly   — completeness: account x month usage rollup
```

Why this split: staging isolates source quirks from the rest of the DAG;
intermediate holds logic that's reused by more than one mart (so it isn't
copy-pasted); marts are the only layer analysts/BI tools should touch.
`raw_` tables live in the warehouse but aren't dbt models — dbt's job starts
at staging (see §6 for why the load step is kept outside dbt in this design).

---

## 3. The waterfall logic

**Grain:** `fct_mrr_waterfall` is one row per `(account_id, month_date)`.
`fct_mrr_waterfall_monthly` aggregates that up to one row per `month_date`.

For every account and every month in the window, `int_account_mrr_changes`
compares that month's MRR to the prior month's and buckets the change:

| movement_type  | condition                                              |
|----------------|---------------------------------------------------------|
| `new`          | MRR was $0 (or account didn't exist) last month, is >$0 now, and the account has **never** had MRR before |
| `reactivation` | Same as above, but the account **did** have MRR at some earlier point (i.e. it churned and came back) |
| `expansion`    | MRR was >$0 last month and is higher this month          |
| `contraction`  | MRR was >$0 last month and is lower — but still >$0 — this month |
| `churn`        | MRR was >$0 last month and is exactly $0 this month       |
| `retained`     | MRR unchanged, >$0 both months                            |
| `no_activity`  | $0 both months (never signed up yet, or churned long ago) |

`fct_mrr_waterfall_monthly` then reconciles:

```
beginning_mrr + new_mrr + expansion_mrr + contraction_mrr + churned_mrr + reactivation_mrr = ending_mrr
```

(`contraction_mrr` and `churned_mrr` are stored as **negative** numbers, so
this is a straight sum — that's why the mart is named a "waterfall": every
bucket adds or subtracts from the running total, and the columns can be
charted directly as a waterfall/bridge chart.) This identity, plus the fact
that month M's `ending_mrr` equals month M+1's `beginning_mrr`, is enforced
by two custom dbt tests (see §5).

---

## 4. Key modeling decisions & assumptions

1. **Accounts can hold multiple concurrently-active subscriptions.**
   The raw data isn't a clean "one active contract per account" history —
   many accounts have several `subscription_id` rows open at the same time,
   with independent start/end dates (e.g. multi-team or multi-product
   contracts). We modeled **account MRR = sum of all its active, non-trial
   subscriptions in a given month**, rather than assuming one subscription
   per account. This is the single most important assumption in the model —
   flagged here explicitly because it isn't stated in the brief.

2. **Trials contribute $0 to MRR.** `is_trial = true` subscriptions are kept
   in staging (for completeness/analysis) but excluded from every revenue
   calculation via `revenue_mrr_amount`.

3. **"Expansion" includes new concurrent subscriptions, not just plan
   upgrades.** Because of (1), an account adding a second contract counts as
   MRR growth this month and is bucketed as `expansion`, even though the
   source `upgrade_flag` wasn't set on any single row. This is intentional —
   from the CFO's perspective, more revenue from an existing customer *is*
   expansion, regardless of whether it came from a plan upgrade or a new
   contract. It does mean `expansion_mrr` is not directly reconcilable to
   `sum(upgrade_flag)` in `subscriptions.csv`; that's expected.

4. **Churn is account-level, not subscription-level.** An account only
   lands in the `churn` bucket when *all* of its MRR drops to $0 in a month.
   Losing one of several concurrent subscriptions while others remain active
   is `contraction`, not `churn`. This matches how most SaaS finance teams
   define gross/logo churn vs. contraction.

5. **Reporting window is fixed, not dynamic.** `waterfall_start_month` /
   `waterfall_end_month` (`dbt_project.yml` vars) are hardcoded to
   `2023-01-01`–`2024-12-01`, matching the full span of the data. In
   production these would resolve dynamically (min/max of loaded data, or
   the current run date) — see §6.

6. **`churn_events.csv` is used for enrichment, not classification.**
   Movement type is derived purely from the MRR time series (source of
   truth, always available). `churn_events` (reason_code, refund_amount,
   preceding_upgrade/downgrade flags) is left-joined onto churn-month rows
   in `fct_mrr_waterfall` for context/drill-down, since it's sparser
   (600 events) than the subscription grain and not every MRR-drop-to-zero
   month necessarily has a matching event logged.

7. **Data quality finding:** `feature_usage.csv`'s `usage_id` has 21
   hash collisions across genuinely different events (different
   subscription/date/feature per pair — not true duplicates). Flagged as a
   `warn`-severity source test rather than blocking the build, and worked
   around with a hash-based surrogate key (`usage_pk`) in `stg_feature_usage`.
   `feature_usage`/`support_tickets` are staged and rolled up into marts for
   completeness of the full data model, but aren't consumed by the revenue
   waterfall itself — a natural next step would be a customer health-score
   model joining them against churn/contraction risk.

---

## 5. Testing

55 dbt tests total, well above the 5-test minimum:

- **Generic tests** (`unique`, `not_null`, `relationships`, `accepted_values`,
  `dbt_utils.accepted_range`, `dbt_utils.unique_combination_of_columns`) on
  every primary key, foreign key, and enum-like column across all layers.
- **3 custom singular tests** on the waterfall's business logic
  (`tests/`):
  - `test_mrr_delta_arithmetic.sql` — at account-month grain, `prior_mrr + mrr_delta = current_mrr`, always.
  - `test_mrr_waterfall_reconciles.sql` — at the monthly summary grain, `beginning_mrr + net_new_mrr = ending_mrr`.
  - `test_mrr_waterfall_month_chain_continuous.sql` — one month's `ending_mrr` equals the next month's `beginning_mrr` (no gaps/double-counting).

Run just the tests: `dbt test --profiles-dir .`

---

## 6. Production-readiness notes

Kept brief here since this is covered in the (later) presentation, but
flagging the main ones inline:

- **Load step**: `load_raw_data.py` is a stand-in for a real EL tool
  (Fivetran/Airbyte/Meltano) or a lightweight ingestion Lambda. In
  production, dbt wouldn't touch the CSV-to-warehouse step at all — sources
  would already be landed on a schedule.
- **Incremental models**: `int_subscription_monthly` and the downstream
  monthly aggregations are full-refresh views/tables today (small data).
  At real scale, `int_account_monthly_mrr` and `fct_mrr_waterfall` are
  natural candidates for `materialized='incremental'` with a monthly
  `is_incremental()` filter, since only the current month's MRR actually
  changes day to day.
- **Freshness**: no `loaded_at_field` + `freshness` blocks configured yet
  since this is a static extract; would add these on `sources.yml` against
  real pipelines, plus a `dbt source freshness` check in the orchestration
  DAG.
- **Monitoring**: today's tests catch known failure modes retrospectively
  on each run. In production I'd add anomaly-detection tests
  (`dbt_utils.recency`, or elementary/re_data-style volume & distribution
  monitors) on `fct_mrr_waterfall_monthly` specifically, since a silent
  break in the waterfall logic is a CFO-visible, high-trust-cost bug.
- **Dynamic window bounds**: replace the hardcoded `waterfall_start_month`/
  `waterfall_end_month` vars with a query against `min(signup_date)` and
  `{{ run_started_at }}` (or last full month).

---

## 7. Repo layout

```
company_x/
├── dbt_project.yml
├── packages.yml
├── profiles.yml            # local dev profile (DuckDB) — safe to commit, no secrets
├── load_raw_data.py        # simulated EL step
├── raw_data/                # the 5 source CSVs
├── models/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
└── tests/                   # custom singular tests
```
