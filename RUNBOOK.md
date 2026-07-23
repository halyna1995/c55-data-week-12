# RUNBOOK

<!-- Replace every TODO with real content. Another student should be able to
     operate your DAG from this file alone, without reading your Python. -->

## How to trigger the DAG manually

1. Start the local stack from the project root with `astro dev start`.
2. Open the Airflow UI and confirm that the `azure_pg` connection exists.
3. Open `taxi_pipeline`, unpause it, and click **Trigger**.
4. In Trigger Options, pass a real past logical date such as `2024-01-01`.
   If the UI does not expose a logical-date field, use this run configuration:
   `{"target_date": "2024-01-01"}`.
5. Open the new run and confirm the order `ingest_taxi_month → dbt_run → dbt_test`.

Do not trigger the DAG for a future or unpublished TLC month. Such a run returns HTTP 403 because the parquet file does not exist yet.

## How to run a backfill

The DAG uses a monthly schedule, so seven assignment runs require seven months. In PowerShell run this as one line, without Bash backslashes:

```powershell
astro dev run backfill create --dag-id taxi_pipeline --from-date 2024-01-01 --to-date 2024-07-31 --max-active-runs 1
```

If the DAG is paused, create the backfill first and then unpause it in the UI. Wait until all runs finish before repeating the range. To repeat completed dates for the idempotency proof, use:

```powershell
astro dev run backfill create --dag-id taxi_pipeline --from-date 2024-01-01 --to-date 2024-07-31 --max-active-runs 1 --reprocess-behavior completed
```

## How to inspect task logs

TODO

## Top 3 likely failures and first response

1. TODO — symptom, first check, fix
2. TODO
3. TODO
