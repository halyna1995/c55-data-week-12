# Assignment report

<!-- Replace every TODO. Keep it short: a few sentences per section. -->

## Schedule choice and reason

I chose `@monthly` because TLC publishes the taxi parquet files by month and the ingest task owns one monthly partition per Airflow run. This prevents a daily schedule from repeatedly loading the same monthly file. Normal operation uses `catchup=False`; historical data is loaded deliberately with `backfill create`.

## Task dependency graph

The strict dependency chain is:

```text
ingest_taxi_month → dbt_run → dbt_test
```

The ingest task must finish before dbt builds the models, and `dbt_test` must run only after a successful build. If ingestion fails, Airflow blocks both downstream tasks instead of transforming stale or incomplete data.

## dbt project used

I used the class reference Week 10 dbt project copied into `include/dbt_project/`. Airflow runs dbt through `uvx --python 3.11` because the Astro runtime uses Python 3.14 and stable dbt-core is not compatible with that interpreter.

## Logical-date parameterization and idempotency

The ingest task reads the current Airflow run context through `_partition_date_from_context()`. Scheduled and backfill runs use `dag_run.logical_date`; a manual run may use an explicitly supplied past logical date or `target_date` configuration. The date selects both the TLC parquet URL and the monthly database partition.

Before appending a month, the task deletes only rows whose `lpep_pickup_datetime` belongs to that `YYYY-MM`. Therefore rerunning the same logical month ends with one copy of that month rather than duplicate rows.

## Retry configuration

The DAG configures two retries with a two-minute delay. Retries are useful for transient network or database failures. They do not solve deterministic failures such as a 403 for an unpublished file or invalid SQL.

## One debugging case I resolved

A manual run requested `green_tripdata_2026-07.parquet` and failed with HTTP 403. Reading the ingest log showed that a manual Airflow 3 run had no past logical date and fell back to the current date. I fixed the workflow by requiring a past logical date for manual runs and by using explicit historical dates for backfills.

## Backfill and idempotency evidence

Command used for the required seven monthly runs:

```powershell
astro dev run backfill create --dag-id taxi_pipeline --from-date 2024-01-01 --to-date 2024-07-31 --max-active-runs 1
```

Command used to repeat completed runs:

```powershell
astro dev run backfill create --dag-id taxi_pipeline --from-date 2024-01-01 --to-date 2024-07-31 --max-active-runs 1 --reprocess-behavior completed
```

SQL used to record row counts:

```sql
SELECT
    to_char(lpep_pickup_datetime, 'YYYY-MM') AS month,
    count(*) AS row_count
FROM airflow_<my_role>.raw_trips
WHERE lpep_pickup_datetime >= TIMESTAMP '2024-01-01'
  AND lpep_pickup_datetime < TIMESTAMP '2024-08-01'
GROUP BY 1
ORDER BY 1;
```

### Results to add after running

| Month | First backfill count | Repeated backfill count |
|---|---:|---:|
| 2024-01 | 56549 | 56549 |
| 2024-02 | 53571 | 53571 |
| 2024-03 | 57447 | 57447 |
| 2024-04 | 56467 | 56467 |
| 2024-05 | 60994 | 60994 |
| 2024-06 | 54735 | 54735 |
| 2024-07 | 51811 | 51811 |

The two columns must be identical before submission.

## Shared Airflow deployment proof

- Namespaced DAG ID: halyna_taxi_pipeline
- Student tag:  student:halyna
- Merged shared-deploy PR: https://github.com/HackYourAssignment/c55-data-week-12/pull/7
- Shared UI screenshot: `evidence/local_green_run.png`

If the shared VM was unavailable, state that explicitly here and include the local green-run evidence instead.


<!-- Target tier: also document your {{ ds }} parameter usage and the
     backfill command(s) you ran, with before/after row counts. -->
