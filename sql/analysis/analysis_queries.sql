-- =====================================================================
-- SQL Analysis Tasks
-- =====================================================================

-- Task 1: Average global_active_power_kw by hour_of_day and day_type
SELECT
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    DATEPART(HOUR, reading_timestamp) AS hour_of_day,
    AVG(global_active_power_kw) AS avg_global_active_power_kw
FROM fact_energy_readings
GROUP BY
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END,
    DATEPART(HOUR, reading_timestamp)
ORDER BY day_type, hour_of_day;

-- Task 2: Top 10 highest-severity power-quality anomalies by voltage deviation
SELECT TOP 10
    reading_timestamp,
    anomaly_type,
    voltage_v,
    severity,
    ABS(voltage_v - 238) AS voltage_deviation   -- midpoint
FROM dbo.PowerQualityAnomalies
ORDER BY voltage_deviation DESC;

-- Task 3: View summarizing daily total energy consumption (kWh) over the full archive
CREATE OR ALTER VIEW dbo.vw_DailyEnergyConsumption AS
SELECT
    CAST(reading_timestamp AS DATE) AS reading_date,
    SUM(global_active_power_kw / 60.0) AS total_kwh   -- readings are per-minute; kW/60 = kWh per reading
FROM fact_energy_readings
WHERE global_active_power_kw IS NOT NULL
GROUP BY CAST(reading_timestamp AS DATE);

SELECT * FROM dbo.vw_DailyEnergyConsumption ORDER BY reading_date;

-- Task 4: Rank hours of the day by average power draw using a window function
SELECT
    hour_of_day,
    avg_power,
    RANK() OVER (ORDER BY avg_power DESC) AS power_rank
FROM (
    SELECT
        DATEPART(HOUR, reading_timestamp) AS hour_of_day,
        AVG(global_active_power_kw) AS avg_power
    FROM fact_energy_readings
    GROUP BY DATEPART(HOUR, reading_timestamp)
) hourly_avg
ORDER BY power_rank;

-- Task 5: Time windows where streaming average power draw exceeded the documented alert threshold
SELECT *
FROM dbo.RealtimeMeterTrend
WHERE avg_global_active_power_kw > 2.0
  AND ingestion_source = 'Streaming'
ORDER BY time_window DESC;

-- Task 6: Running daily total of ingested readings by ingestion_source
SELECT
    reading_date,
    ingestion_source,
    daily_count,
    SUM(daily_count) OVER (
        PARTITION BY ingestion_source ORDER BY reading_date
        ROWS UNBOUNDED PRECEDING
    ) AS running_total
FROM (
    SELECT
        CAST(reading_timestamp AS DATE) AS reading_date,
        ingestion_source,
        COUNT(*) AS daily_count
    FROM fact_energy_readings
    GROUP BY CAST(reading_timestamp AS DATE), ingestion_source
) daily_counts
ORDER BY ingestion_source, reading_date;

-- Task 7: Days with zero recorded anomalies despite high average power draw
SELECT
    d.reading_date,
    d.avg_daily_power
FROM (
    SELECT
        CAST(reading_timestamp AS DATE) AS reading_date,
        AVG(global_active_power_kw) AS avg_daily_power
    FROM fact_energy_readings
    GROUP BY CAST(reading_timestamp AS DATE)
) d
WHERE d.avg_daily_power > (SELECT AVG(global_active_power_kw) FROM fact_energy_readings)
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.PowerQualityAnomalies a
      WHERE CAST(a.reading_timestamp AS DATE) = d.reading_date
  )
ORDER BY d.avg_daily_power DESC;

-- Task 8: Share of total power draw attributable to each sub-meter vs. unmetered
SELECT
    SUM(sub_metering_kitchen_wh) AS total_kitchen_wh,
    SUM(sub_metering_laundry_wh) AS total_laundry_wh,
    SUM(sub_metering_waterheater_ac_wh) AS total_waterheater_ac_wh,
    SUM(unmetered_power_wh) AS total_unmetered_wh,
    SUM(sub_metering_kitchen_wh) * 100.0 / NULLIF(
        SUM(sub_metering_kitchen_wh) + SUM(sub_metering_laundry_wh) +
        SUM(sub_metering_waterheater_ac_wh) + SUM(unmetered_power_wh), 0
    ) AS pct_kitchen,
    SUM(sub_metering_laundry_wh) * 100.0 / NULLIF(
        SUM(sub_metering_kitchen_wh) + SUM(sub_metering_laundry_wh) +
        SUM(sub_metering_waterheater_ac_wh) + SUM(unmetered_power_wh), 0
    ) AS pct_laundry,
    SUM(sub_metering_waterheater_ac_wh) * 100.0 / NULLIF(
        SUM(sub_metering_kitchen_wh) + SUM(sub_metering_laundry_wh) +
        SUM(sub_metering_waterheater_ac_wh) + SUM(unmetered_power_wh), 0
    ) AS pct_waterheater_ac,
    SUM(unmetered_power_wh) * 100.0 / NULLIF(
        SUM(sub_metering_kitchen_wh) + SUM(sub_metering_laundry_wh) +
        SUM(sub_metering_waterheater_ac_wh) + SUM(unmetered_power_wh), 0
    ) AS pct_unmetered
FROM fact_energy_readings;

-- Task 9: View summarizing proportion of records by ingestion_source
CREATE OR ALTER VIEW dbo.vw_IngestionSourceProportion AS
SELECT
    ingestion_source,
    COUNT(*) AS record_count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS pct_of_total
FROM fact_energy_readings
GROUP BY ingestion_source;

SELECT * FROM dbo.vw_IngestionSourceProportion;

-- Task 10: Most recent time window with the highest average power draw
SELECT TOP 1
    time_window,
    avg_global_active_power_kw
FROM (
    SELECT
        time_window,
        avg_global_active_power_kw,
        RANK() OVER (ORDER BY avg_global_active_power_kw DESC) AS power_rank
    FROM dbo.RealtimeMeterTrend
) ranked
ORDER BY power_rank ASC, time_window DESC;
