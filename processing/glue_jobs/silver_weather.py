import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv, ["JOB_NAME", "SILVER_PATH", "BRONZE_PATH", "CATALOG_DB"]
)

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", args["SILVER_PATH"])
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")

db = args["CATALOG_DB"]
table = f"glue_catalog.{db}.silver_weather"

# Read raw JSON (weather directory has many small JSONs)
raw = spark.read.option("recursiveFileLookup", "true").json(
    f"{args['BRONZE_PATH']}raw/weather/"
)

# Flatten payload.current
silver = (
    raw.select(
        F.col("city").alias("city"),
        F.col("lat").cast("double").alias("lat"),
        F.col("lon").cast("double").alias("lon"),
        F.col("ingested_at").cast("timestamp").alias("ingested_at"),
        F.col("payload.current.time").cast("timestamp").alias("observed_at"),
        F.col("payload.current.temperature_2m").cast("double").alias("temp_c"),
        F.col("payload.current.precipitation").cast("double").alias("precip_mm"),
        F.col("payload.current.weather_code").cast("int").alias("weather_code"),
        F.col("payload.current.wind_speed_10m").cast("double").alias("wind_kph"),
        F.col("payload.current.relative_humidity_2m").cast("int").alias("humidity_pct"),
    )
    # 1 row per (city, observed_at) — keep latest ingest if duplicates
    .withColumn("_rn", F.row_number().over(
        __import__("pyspark.sql.window", fromlist=["Window"])
        .Window.partitionBy("city", "observed_at").orderBy(F.col("ingested_at").desc())
    ))
    .filter(F.col("_rn") == 1)
    .drop("_rn")
)

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {table} (
  city         STRING,
  lat          DOUBLE,
  lon          DOUBLE,
  ingested_at  TIMESTAMP,
  observed_at  TIMESTAMP,
  temp_c       DOUBLE,
  precip_mm    DOUBLE,
  weather_code INT,
  wind_kph     DOUBLE,
  humidity_pct INT
)
USING iceberg
PARTITIONED BY (days(observed_at))
""")

silver.createOrReplaceTempView("incoming")
spark.sql(f"""
MERGE INTO {table} t
USING incoming s
  ON t.city = s.city AND t.observed_at = s.observed_at
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

count = spark.sql(f"SELECT COUNT(*) AS c FROM {table}").collect()[0]["c"]
print(f"✅ silver_weather rows: {count}")

job.commit()
