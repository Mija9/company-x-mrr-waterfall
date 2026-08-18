"""
load_raw_data.py
-----------------
Simulates the EL (Extract & Load) step of an ELT pipeline.

In production this would be handled by a connector (Fivetran, Airbyte, Stitch)
or a custom ingestion job landing data in the warehouse. For this exercise we
load the provided CSV extracts into a local DuckDB file under a `raw` schema,
with a `raw_` table prefix, which dbt then reads from via `sources.yml`.

Run once before `dbt run`:
    python load_raw_data.py
"""
import duckdb
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(HERE, "company_x.duckdb")
RAW_DIR = os.path.join(HERE, "raw_data")

TABLES = {
    "raw_accounts": "accounts.csv",
    "raw_subscriptions": "subscriptions.csv",
    "raw_feature_usage": "feature_usage.csv",
    "raw_support_tickets": "support_tickets.csv",
    "raw_churn_events": "churn_events.csv",
}

def main():
    con = duckdb.connect(DB_PATH)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw;")
    for table, csv_file in TABLES.items():
        csv_path = os.path.join(RAW_DIR, csv_file)
        print(f"Loading {csv_file} -> raw.{table}")
        con.execute(f"""
            CREATE OR REPLACE TABLE raw.{table} AS
            SELECT * FROM read_csv_auto('{csv_path}', header=True, sample_size=-1)
        """)
        count = con.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]
        print(f"  -> {count} rows loaded")
    con.close()
    print("Done. DuckDB file at:", DB_PATH)

if __name__ == "__main__":
    main()
