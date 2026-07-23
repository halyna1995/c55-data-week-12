-- Mart: daily borough trip statistics.
-- Grain: one row per (pickup_borough, pickup_date).
-- Used to answer: trip volume, revenue, tipping behaviour, and distance profile
-- per borough per day for January 2024.

WITH trips AS (
    SELECT *
    FROM {{ ref('stg_trips') }}
),

zones AS (
    SELECT *
    FROM {{ ref('stg_zones') }}
)

SELECT
    z.borough as pickup_borough,
    t.pickup_datetime::date as pickup_date,
    count(*)::bigint as trip_count,
    sum(t.fare_amount)::numeric as total_fare,
    avg(t.tip_pct)::numeric as avg_tip_pct,
    avg(t.trip_distance)::numeric as avg_trip_distance
FROM trips t
inner join zones z
    on t.pickup_location_id = z.location_id
group by
    z.borough,
    t.pickup_datetime::date