-- Section 5 — Database Design: Schema DDL
-- Target: Azure SQL Database (EnergyGridDB)

-- ---------------------------------------------------------------------
-- Table: dim_meters
-- ---------------------------------------------------------------------
CREATE TABLE dim_meters (
    meter_id VARCHAR(20) NOT NULL PRIMARY KEY,
    location_note VARCHAR(120) NULL,
    submeter_count INT NULL
);

-- ---------------------------------------------------------------------
-- Table: fact_energy_readings
-- ---------------------------------------------------------------------
CREATE TABLE fact_energy_readings (
    reading_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    meter_id VARCHAR(20) NOT NULL,
    reading_timestamp DATETIME2 NOT NULL,
    global_active_power_kw DECIMAL(6,3) NULL,
    global_reactive_power_kw DECIMAL(6,3) NULL,
    voltage_v DECIMAL(6,2) NULL,
    global_intensity_a DECIMAL(6,2) NULL,
    sub_metering_kitchen_wh DECIMAL(8,2) NULL,
    sub_metering_laundry_wh DECIMAL(8,2) NULL,
    sub_metering_waterheater_ac_wh DECIMAL(8,2) NULL,
    unmetered_power_wh DECIMAL(8,2) NULL,
    is_weekend BIT NULL,
    ingestion_source VARCHAR(12) NOT NULL,
    ingestion_timestamp DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_fact_meter FOREIGN KEY (meter_id)
        REFERENCES dim_meters (meter_id),

-- Section 6 validation rules, enforced at the schema level

    CONSTRAINT CK_fact_power_nonnegative
        CHECK (global_active_power_kw IS NULL OR global_active_power_kw >= 0),
    CONSTRAINT CK_fact_ingestion_source
        CHECK (ingestion_source IN ('Batch', 'Streaming'))
);

CREATE INDEX IX_fact_reading_timestamp ON fact_energy_readings (reading_timestamp);
CREATE INDEX IX_fact_ingestion_source ON fact_energy_readings (ingestion_source);

-- ---------------------------------------------------------------------
-- Table: dbo.ConsumptionPatterns  (Use Case 1)
-- Aggregated from fact_energy_readings during ETL.
-- ---------------------------------------------------------------------
CREATE TABLE dbo.ConsumptionPatterns (
    pattern_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    day_type VARCHAR(10) NOT NULL,
    hour_of_day TINYINT NOT NULL,
    avg_global_active_power_kw DECIMAL(6,3) NULL,
    avg_kitchen_wh DECIMAL(8,2) NULL,
    avg_laundry_wh DECIMAL(8,2) NULL,
    avg_waterheater_ac_wh DECIMAL(8,2) NULL,

    CONSTRAINT CK_pattern_daytype CHECK (day_type IN ('Weekday', 'Weekend')),
    CONSTRAINT CK_pattern_hour CHECK (hour_of_day BETWEEN 0 AND 23)
);

-- ---------------------------------------------------------------------
-- Table: dbo.PowerQualityAnomalies  (Use Case 2)
-- ---------------------------------------------------------------------
CREATE TABLE dbo.PowerQualityAnomalies (
    anomaly_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    reading_timestamp DATETIME2 NOT NULL,
    anomaly_type VARCHAR(30) NOT NULL,
    voltage_v DECIMAL(6,2) NULL,
    global_reactive_power_kw DECIMAL(6,3) NULL,
    global_intensity_a DECIMAL(6,2) NULL,
    severity VARCHAR(10) NOT NULL,

    CONSTRAINT CK_anomaly_severity CHECK (severity IN ('Low', 'Medium', 'High'))
);

-- ---------------------------------------------------------------------
-- Table: dbo.RealtimeMeterTrend  (Use Case 3)
-- ---------------------------------------------------------------------
CREATE TABLE dbo.RealtimeMeterTrend (
    trend_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    time_window DATETIME2 NOT NULL,
    ingestion_source VARCHAR(12) NOT NULL,
    avg_global_active_power_kw DECIMAL(6,3) NULL,
    reading_count INT NULL,
    alert_flag BIT NULL
);

-- ---------------------------------------------------------------------
-- Seed the single known meter (real data has no household identifier; this is the intentionally thin, forward-looking dimension row)
-- ---------------------------------------------------------------------
INSERT INTO dim_meters (meter_id, location_note, submeter_count)
VALUES ('HOUSE_001', 'Sceaux, France (single-household reference dataset)', 3);

