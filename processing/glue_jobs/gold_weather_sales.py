import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "SILVER_PATH", "GOLD_PATH", "BRONZE_PATH", "SILVER_DB", "CATALOG_DB"],
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
silver_db = args["SILVER_DB"]

purchases = spark.table(f"glue_catalog.{silver_db}.silver_purchases")
# bronze_customers is a Parquet EXTERNAL_TABLE (not Iceberg), so read directly from S3
customers = spark.read.parquet(
    f"{args['BRONZE_PATH']}cdc/purchases/public/customers/"
)
weather = spark.table(f"glue_catalog.{silver_db}.silver_weather")
reviews = spark.table(f"glue_catalog.{silver_db}.silver_reviews")

# Dedup customers to latest per customer_id
from pyspark.sql.window import Window
wc = Window.partitionBy("customer_id").orderBy(F.col("_dms_timestamp").desc())
customers_dedup = (
    customers
    .withColumn("_rn", F.row_number().over(wc))
    .filter(F.col("_rn") == 1)
    .drop("_rn")
    .select("customer_id", "region")
)

# Aggregate weather to hourly
weather_h = (
    weather
    .withColumn("weather_hour", F.date_trunc("hour", "observed_at"))
    .groupBy("city", "weather_hour")
    .agg(
        F.avg("temp_c").alias("avg_temp_c"),
        F.sum("precip_mm").alias("total_precip_mm"),
        F.first("weather_code").alias("weather_code"),
        F.avg("wind_kph").alias("avg_wind_kph"),
    )
)

# Aggregate reviews to daily per product
reviews_d = (
    reviews
    .withColumn("review_date", F.to_date("review_ts"))
    .groupBy("product_id", "review_date")
    .agg(
        F.avg("sentiment_score").alias("avg_sentiment"),
        F.count("*").alias("review_count"),
    )
)

# City mapping: region → city (simple mapping — adjust for real world)
CITY_MAP = {"us-east": "NewYork", "us-west": "Sydney", "eu": "London"}
map_expr = F.create_map([F.lit(k) for pair in CITY_MAP.items() for k in pair])

p = (
    purchases.alias("p")
    .join(customers_dedup.alias("c"), "customer_id", "left")
    .withColumn("city", map_expr[F.col("region")])
    .withColumn("sale_hour", F.date_trunc("hour", "purchase_ts"))
    .withColumn("sale_date", F.to_date("purchase_ts"))
)

joined = (
    p.alias("p")
    .join(weather_h.alias("w"),
          (F.col("p.city") == F.col("w.city")) &
          (F.col("p.sale_hour") == F.col("w.weather_hour")),
          "left")
    .join(reviews_d.alias("r"),
          (F.col("p.product_id") == F.col("r.product_id")) &
          (F.col("p.sale_date") == F.col("r.review_date")),
          "left")
)

gold = (
    joined
    .groupBy(
        F.col("sale_date").alias("sale_date"),
        F.col("region").alias("region"),
        F.when(F.col("total_precip_mm") > 1, "rainy").otherwise("dry").alias("weather_bucket"),
    )
    .agg(
        F.count("*").alias("orders"),
        F.round(F.sum("amount"), 2).alias("revenue"),
        F.round(F.avg("amount"), 2).alias("avg_order_value"),
        F.round(F.avg("avg_temp_c"), 1).alias("avg_temp_c"),
        F.round(F.avg("avg_sentiment"), 3).alias("avg_review_sentiment"),
    )
    .withColumn("_updated_at", F.current_timestamp())
)

gold_table = f"glue_catalog.{db}.gold_weather_sales"

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {gold_table} (
  sale_date            DATE,
  region               STRING,
  weather_bucket       STRING,
  orders               BIGINT,
  revenue              DECIMAL(18,2),
  avg_order_value      DECIMAL(18,2),
  avg_temp_c           DOUBLE,
  avg_review_sentiment DOUBLE,
  _updated_at          TIMESTAMP
)
USING iceberg
""")

gold.createOrReplaceTempView("gold_incoming")
spark.sql(f"INSERT OVERWRITE {gold_table} SELECT * FROM gold_incoming")

count = spark.sql(f"SELECT COUNT(*) AS c FROM {gold_table}").collect()[0]["c"]
print(f"✅ gold_weather_sales rows: {count}")

job.commit()
