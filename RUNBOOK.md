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

Open `taxi_pipeline → Runs → the failed run → the red task → Logs`. Read upward from the final generic message until the first concrete exception, such as `HTTPError`, `DatabaseError`, `Compilation Error`, or `Env var required but not provided`. Also check **Rendered Templates** for `dbt_run` and `dbt_test` to confirm the resolved database host, user, database, and schema. Passwords must remain redacted.

## Top 3 likely failures and first response

1. **`ingest_taxi_month` fails with HTTP 403/404.** Check the requested URL and logical date in the log. A future month or mistyped path is deterministic, so retries will not fix it. Trigger/backfill a published month and correct the URL or date range.
2. **PostgreSQL connection or permission failure.** Confirm `AIRFLOW_STUDENT` in `.env`, then verify `azure_pg` in Admin → Connections. The login and schema name must match, for example role `halyna` writes to `airflow_halyna`. Do not commit credentials.
3. **`dbt_run` fails.** Read the first dbt `Runtime Error` or `Compilation Error`, not only the final Bash exit code. Confirm `include/dbt_project/profiles.yml` exists, required `PG_*` variables are rendered, and `dbt deps` runs before `dbt run`.

## Safe recovery and escalation

Clear and retry one task only for a transient network or database interruption. Use a backfill after a code or business-logic fix that affects several partitions. If the shared scheduler, shared `azure_pg` connection, or shared VM is broken, do not edit shared settings; report the issue to the teacher.