"""
Loads the CSV files under home-credit-default-risk/ into PostgreSQL.
Source tables go to the raw schema, metadata files to the public schema.

Uses pandas/SQLAlchemy to create the schema and PostgreSQL's native COPY
to move the data (much faster than row-by-row INSERT, which matters for
files with millions of rows).

Connection settings are read from .env (see docker-compose.yml).

Usage:
    python load_to_postgres.py
"""

import os
import time
from io import StringIO
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

DATA_DIR = Path(__file__).parent / "home-credit-default-risk"

PG_USER = os.environ["POSTGRES_USER"]
PG_PASSWORD = os.environ["POSTGRES_PASSWORD"]
PG_DB = os.environ["POSTGRES_DB"]
PG_PORT = os.environ.get("POSTGRES_PORT", "5432")
PG_HOST = "localhost"

DB_URL = f"postgresql+psycopg2://{PG_USER}:{PG_PASSWORD}@{PG_HOST}:{PG_PORT}/{PG_DB}"
PG_CONN_KWARGS = dict(
    host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD
)

CHUNKSIZE = 200_000

SCHEMAS = ("raw", "stg", "mart")

# file name -> (schema, table name)
FILES = {
    "application_train.csv": ("raw", "application_train"),
    "application_test.csv": ("raw", "application_test"),
    "bureau.csv": ("raw", "bureau"),
    "bureau_balance.csv": ("raw", "bureau_balance"),
    "POS_CASH_balance.csv": ("raw", "pos_cash_balance"),
    "credit_card_balance.csv": ("raw", "credit_card_balance"),
    "previous_application.csv": ("raw", "previous_application"),
    "installments_payments.csv": ("raw", "installments_payments"),
    "HomeCredit_columns_description.csv": ("public", "columns_description"),
    "sample_submission.csv": ("public", "sample_submission"),
}


def read_csv_chunks(csv_path: Path, chunksize: int):
    """Tries UTF-8 first and falls back to Windows-1252 (used by some metadata files)."""
    try:
        yield from pd.read_csv(csv_path, chunksize=chunksize, low_memory=False)
    except UnicodeDecodeError:
        yield from pd.read_csv(
            csv_path, chunksize=chunksize, low_memory=False, encoding="cp1252"
        )


def load_csv(engine, conn, csv_path: Path, schema: str, table_name: str) -> None:
    print(f"[{schema}.{table_name}] loading: {csv_path.name}")
    start = time.time()
    total_rows = 0

    for i, chunk in enumerate(read_csv_chunks(csv_path, CHUNKSIZE)):
        chunk.columns = [c.strip().lower() for c in chunk.columns]

        if i == 0:
            # create the table/schema from the first chunk (with 0 rows)
            chunk.head(0).to_sql(
                table_name, engine, schema=schema, if_exists="replace", index=False
            )

        buf = StringIO()
        chunk.to_csv(buf, index=False, header=False, na_rep="")
        buf.seek(0)
        with conn.cursor() as cur:
            cur.copy_expert(
                f'COPY "{schema}"."{table_name}" FROM STDIN WITH (FORMAT csv, NULL \'\')',
                buf,
            )
        conn.commit()

        total_rows += len(chunk)
        print(f"  ... {total_rows:,} rows written", end="\r")

    elapsed = time.time() - start
    print(f"[{schema}.{table_name}] done: {total_rows:,} rows, {elapsed:.1f} s")


def main():
    engine = create_engine(DB_URL)
    conn = psycopg2.connect(**PG_CONN_KWARGS)

    try:
        with conn.cursor() as cur:
            for schema in SCHEMAS:
                cur.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}"')
        conn.commit()

        for filename, (schema, table_name) in FILES.items():
            csv_path = DATA_DIR / filename
            if not csv_path.exists():
                print(f"[warning] file not found, skipping: {csv_path}")
                continue
            load_csv(engine, conn, csv_path, schema, table_name)
    finally:
        conn.close()

    print("\nAll files loaded.")


if __name__ == "__main__":
    main()
