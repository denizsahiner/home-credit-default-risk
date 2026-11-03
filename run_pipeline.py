"""
Builds the data pipeline end to end: CSV -> raw -> stg -> mart.

Files under sql/ run in name order; each one is idempotent.
Connection settings are read from .env.

Usage:
    python run_pipeline.py              # CSV load + all SQL steps
    python run_pipeline.py --skip-load  # SQL steps only, when raw is already loaded
"""

import argparse
import time
from pathlib import Path

import psycopg2

import load_to_postgres

SQL_DIR = Path(__file__).parent / "sql"


def run_sql_files() -> None:
    conn = psycopg2.connect(**load_to_postgres.PG_CONN_KWARGS)
    # the files contain their own BEGIN/COMMIT blocks
    conn.autocommit = True

    try:
        for sql_path in sorted(SQL_DIR.glob("*.sql")):
            print(f"[sql] {sql_path.name}")
            start = time.time()
            with conn.cursor() as cur:
                cur.execute(sql_path.read_text(encoding="utf-8"))
            print(f"[sql] {sql_path.name} done: {time.time() - start:.1f} s")
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument(
        "--skip-load", action="store_true", help="skip the CSV load"
    )
    args = parser.parse_args()

    if not args.skip_load:
        load_to_postgres.main()
    run_sql_files()
    print("\nPipeline finished.")


if __name__ == "__main__":
    main()
