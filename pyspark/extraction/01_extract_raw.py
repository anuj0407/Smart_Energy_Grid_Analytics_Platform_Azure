# Databricks notebook source
storage_account_name = "segrid"
storage_account_key = "<STORAGE_ACCOUNT_KEY>"  # set via Databricks secret scope  

spark.conf.set(
    f"fs.azure.account.key.{storage_account_name}.dfs.core.windows.net",
    storage_account_key
)

# COMMAND ----------

raw_path = f"abfss://raw@{storage_account_name}.dfs.core.windows.net/"
display(dbutils.fs.ls(raw_path))

# COMMAND ----------

from pyspark.sql.types import StructType, StructField, StringType

schema = StructType([
    StructField("Date", StringType(), True),
    StructField("Time", StringType(), True),
    StructField("Global_active_power", StringType(), True),
    StructField("Global_reactive_power", StringType(), True),
    StructField("Voltage", StringType(), True),
    StructField("Global_intensity", StringType(), True),
    StructField("Sub_metering_1", StringType(), True),
    StructField("Sub_metering_2", StringType(), True),
    StructField("Sub_metering_3", StringType(), True),
])

df_raw = (
    spark.read
    .option("header", "true")
    .option("delimiter", ";")
    .schema(schema)
    .csv(raw_path)
)

print(f"Row count: {df_raw.count()}")
df_raw.printSchema()
display(df_raw.limit(10))

# COMMAND ----------

processed_path = f"abfss://processed@{storage_account_name}.dfs.core.windows.net/energy_readings/"

(
    df_extracted
    .write
    .mode("overwrite")
    .parquet(processed_path)
)

print("Written to processed zone.")
display(dbutils.fs.ls(processed_path))

# COMMAND ----------

