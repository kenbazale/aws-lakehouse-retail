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
table = f"glue_catalog.{db}.silver_reviews"

raw = spark.read.option("recursiveFileLookup", "true").json(
    f"{args['BRONZE_PATH']}raw/reviews/"
)

# reviews is an array — explode
silver = (
    raw.select(F.explode("reviews").alias("r"))
    .select(
        F.col("r.review_id").alias("review_id"),
        F.col("r.product_id").alias("product_id"),
        F.col("r.customer_id").cast("int").alias("customer_id"),
        F.col("r.rating").cast("int").alias("rating"),
        F.col("r.sentiment").alias("sentiment"),
        F.col("r.text").alias("review_text"),
        F.col("r.review_ts").cast("timestamp").alias("review_ts"),
    )
    .withColumn(
        "sentiment_score",
        F.when(F.col("sentiment") == "positive", 1.0)
         .when(F.col("sentiment") == "neutral",  0.0)
         .when(F.col("sentiment") == "negative", -1.0)
         .otherwise(F.lit(0.0))
    )
    .dropDuplicates(["review_id"])
)

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {table} (
  review_id       STRING,
  product_id      STRING,
  customer_id     INT,
  rating          INT,
  sentiment       STRING,
  review_text     STRING,
  review_ts       TIMESTAMP,
  sentiment_score DOUBLE
)
USING iceberg
PARTITIONED BY (days(review_ts))
""")

silver.createOrReplaceTempView("incoming")
spark.sql(f"""
MERGE INTO {table} t
USING incoming s
  ON t.review_id = s.review_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

count = spark.sql(f"SELECT COUNT(*) AS c FROM {table}").collect()[0]["c"]
print(f"✅ silver_reviews rows: {count}")

job.commit()
