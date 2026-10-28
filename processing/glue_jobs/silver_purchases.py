import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

args = getResolvedOptions(sys.argv, ["JOB_NAME", "SILVER_PATH", "CATALOG_DB"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# ---- Iceberg config ----
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", args["SILVER_PATH"])
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")

db = args["CATALOG_DB"]
table = f"glue_catalog.{db}.silver_purchases"

# ---- Read bronze data ----
full_load = spark.read.parquet(
    "s3://retail-lakehouse-dev-bronze-[AWS_ACCOUNT_ID]/cdc/purchases/public/purchases/load/"
)

# Read all dated partition folders (2026/10/23/09/...)
cdc_base = "s3://retail-lakehouse-dev-bronze-[AWS_ACCOUNT_ID]/cdc/purchases/public/purchases/"
try:
    cdc = spark.read.option("recursiveFileLookup", "true").parquet(
        f"{cdc_base}2026/"
    )
except Exception:
    cdc = None

# ---- Normalize ----
def clean(df):
    return (
        df.filter(F.col("Op").isin("I", "U"))
        .withColumn("purchase_ts", F.col("purchase_ts").cast("timestamp"))
        .withColumn("amount", F.col("amount").cast(DecimalType(18, 2)))
        .withColumn("currency", F.upper(F.trim("currency")))
        .withColumn("_dms_timestamp", F.col("_dms_timestamp").cast("timestamp"))
        .select("purchase_id", "customer_id", "product_id", "amount",
                "currency", "purchase_ts", "_dms_timestamp")
    )

full_clean = clean(full_load)

if cdc is not None and cdc.count() > 0:
    cdc_clean = clean(cdc)
    # Union + dedupe by purchase_id, keep latest _dms_timestamp
    from pyspark.sql.window import Window
    w = Window.partitionBy("purchase_id").orderBy(F.col("_dms_timestamp").desc())
    combined = (
        full_clean.unionByName(cdc_clean)
        .withColumn("_rn", F.row_number().over(w))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
    )
else:
    combined = full_clean

# ---- Write Iceberg (create or overwrite) ----
spark.sql(f"""
CREATE TABLE IF NOT EXISTS {table} (
  purchase_id    STRING,
  customer_id    INT,
  product_id     STRING,
  amount         DECIMAL(18,2),
  currency       STRING,
  purchase_ts    TIMESTAMP,
  _dms_timestamp TIMESTAMP
)
USING iceberg
PARTITIONED BY (days(purchase_ts))
""")

combined.createOrReplaceTempView("incoming")

spark.sql(f"""
MERGE INTO {table} t
USING incoming s
  ON t.purchase_id = s.purchase_id
WHEN MATCHED AND s._dms_timestamp >= t._dms_timestamp THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

count = spark.sql(f"SELECT COUNT(*) AS c FROM {table}").collect()[0]["c"]
print(f"✅ silver_purchases rows: {count}")

job.commit()
