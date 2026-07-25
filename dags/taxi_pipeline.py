"""Week 12 assignment starter.

Turn this into a scheduled, parameterized, retryable pipeline. The task
list, the file-by-file map, and the point breakdown are in README.md; the
full brief is in the Week 12 "Assignment: Orchestrated Pipeline" chapter.

This starter parses, so `astro dev start` shows the DAG in the UI, but every
task body raises NotImplementedError and the decorator is not configured yet.
Replace the stubs, wire the tasks together, and fill in the decorator. The
autograder fails while any NotImplementedError remains.
"""


import io
import os
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import requests
from sqlalchemy import text

from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import dag, get_current_context, task


# Local Astro reads AIRFLOW_STUDENT from .env.
# Shared Airflow can use the name of the student's DAG folder.
STUDENT = os.environ.get("AIRFLOW_STUDENT") or Path(__file__).parent.name
SCHEMA = f"airflow_{STUDENT}"

TLC_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"


def find_dbt_dir() -> str:
    """Return the mounted dbt project directory."""

    for candidate in (
        "/usr/local/airflow/include/dbt_project",
        "/opt/airflow/include/dbt_project",
    ):
        if Path(candidate).is_dir():
            return candidate

    return "/usr/local/airflow/include/dbt_project"


DBT_DIR = find_dbt_dir()

DBT = (
    "uvx --python 3.11 "
    "--from 'dbt-core==1.10.*' "
    "--with 'dbt-postgres==1.10.*' "
    "dbt"
)

DBT_ENV = {
    "PG_HOST": "{{ conn.azure_pg.host }}",
    "PG_PORT": "{{ conn.azure_pg.port }}",
    "PG_USER": "{{ conn.azure_pg.login }}",
    "PG_PASSWORD": "{{ conn.azure_pg.password }}",
    "PG_DBNAME": "{{ conn.azure_pg.schema }}",
    "PG_SCHEMA": SCHEMA,
}


def parquet_url_for(ds: str) -> str:
    """Return the TLC green-taxi parquet URL for a logical date."""

    parsed_date = datetime.strptime(ds, "%Y-%m-%d")
    year_month = parsed_date.strftime("%Y-%m")

    return f"{TLC_BASE}/green_tripdata_{year_month}.parquet"


def _partition_date_from_context() -> str:
    """Return the partition date for the current Airflow run."""

    context = get_current_context()
    dag_run = context["dag_run"]
    run_id = context["run_id"]

    # target_date використовується тільки для ручного запуску.
    if run_id.startswith("manual__"):
        target_date = (dag_run.conf or {}).get("target_date")

        if not target_date:
            raise ValueError(
                'Manual run requires '
                'conf={"target_date": "2024-01-01"}.'
            )

        datetime.strptime(target_date, "%Y-%m-%d")
        return target_date

    # Для scheduled і backfill кожен run використовує свій місяць.
    data_interval_start = context.get("data_interval_start")

    if data_interval_start is not None:
        return data_interval_start.strftime("%Y-%m-%d")

    if dag_run.logical_date is not None:
        return dag_run.logical_date.strftime("%Y-%m-%d")

    raise ValueError("Could not determine partition date.")

@dag(
    dag_id="taxi_pipeline",
    schedule="@monthly",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
    },
    tags=["week12", "taxi", "orchestration"],
)
def taxi_pipeline():
    """Download, transform, and test monthly taxi data."""

    @task()
    def ingest_taxi_month() -> int:
        """Download and store one monthly partition idempotently."""

        ds = _partition_date_from_context()
        year_month = ds[:7]
        url = parquet_url_for(ds)

        print(f"Loading partition {year_month} from {url}")

        # Download the monthly parquet file.
        response = requests.get(url, timeout=60)
        response.raise_for_status()

        dataframe = pd.read_parquet(
            io.BytesIO(response.content)
        )

        # Ensure that only the requested logical month is written.
        dataframe["lpep_pickup_datetime"] = pd.to_datetime(
            dataframe["lpep_pickup_datetime"]
        )

        dataframe = dataframe[
            dataframe["lpep_pickup_datetime"]
            .dt.strftime("%Y-%m")
            .eq(year_month)
        ].copy()

        if dataframe.empty:
            raise ValueError(
                f"No rows found for partition {year_month}"
            )

        # Connect to Azure PostgreSQL.
        hook = PostgresHook(
            postgres_conn_id="azure_pg"
        )
        engine = hook.get_sqlalchemy_engine()

        # Create the student's schema.
        with engine.begin() as connection:
            connection.execute(
                text(
                    f'CREATE SCHEMA IF NOT EXISTS "{SCHEMA}"'
                )
            )

        # Create raw_trips if it does not exist yet.
        dataframe.head(0).to_sql(
            "raw_trips",
            engine,
            schema=SCHEMA,
            if_exists="append",
            index=False,
        )

        # Delete only the current month before reloading it.
        # This makes repeated runs idempotent.
        with engine.begin() as connection:
            connection.execute(
                text(
                    f'DELETE FROM "{SCHEMA}".raw_trips '
                    "WHERE to_char("
                    "lpep_pickup_datetime, 'YYYY-MM'"
                    ") = :year_month"
                ),
                {"year_month": year_month},
            )

        # Append the refreshed monthly partition.
        dataframe.to_sql(
            "raw_trips",
            engine,
            schema=SCHEMA,
            if_exists="append",
            index=False,
            method="multi",
            chunksize=1000,
        )

        row_count = len(dataframe)

        print(
            f"Loaded {row_count} rows into "
            f"{SCHEMA}.raw_trips for {year_month}"
        )

        return row_count

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f"{DBT} deps "
            f"--project-dir {DBT_DIR} "
            f"--profiles-dir {DBT_DIR} && "
            f"{DBT} run "
            f"--project-dir {DBT_DIR} "
            f"--profiles-dir {DBT_DIR}"
        ),
        env=DBT_ENV,
        append_env=True,
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"{DBT} test "
            f"--project-dir {DBT_DIR} "
            f"--profiles-dir {DBT_DIR}"
        ),
        env=DBT_ENV,
        append_env=True,
    )

    ingest = ingest_taxi_month()
    ingest >> dbt_run >> dbt_test


taxi_pipeline()