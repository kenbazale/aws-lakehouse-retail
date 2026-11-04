# ---------- IAM role for Glue ETL ----------
resource "aws_iam_role" "glue_etl" {
  name = "${var.project}-${var.env}-glue-etl"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_etl_service" {
  role       = aws_iam_role.glue_etl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_etl" {
  role = aws_iam_role.glue_etl.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.lakehouse["bronze"].arn,
          "${aws_s3_bucket.lakehouse["bronze"].arn}/*",
          aws_s3_bucket.lakehouse["silver"].arn,
          "${aws_s3_bucket.lakehouse["silver"].arn}/*",
          aws_s3_bucket.lakehouse["gold"].arn,
          "${aws_s3_bucket.lakehouse["gold"].arn}/*",
          aws_s3_bucket.lakehouse["scripts"].arn,
          "${aws_s3_bucket.lakehouse["scripts"].arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable",
          "glue:GetTables", "glue:CreateTable", "glue:UpdateTable",
          "glue:DeleteTable", "glue:GetPartition", "glue:GetPartitions",
          "glue:CreatePartition", "glue:UpdatePartition",
          "glue:BatchCreatePartition", "glue:BatchUpdatePartition",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.lakehouse.arn
      }
    ]
  })
}

# ---------- Glue jobs ----------
locals {
  bronze_path      = "s3://${aws_s3_bucket.lakehouse["bronze"].id}/"
  scripts_path     = "s3://${aws_s3_bucket.lakehouse["scripts"].id}/"
  glue_script_base = "s3://${aws_s3_bucket.lakehouse["scripts"].id}/glue"
  silver_path      = "s3://${aws_s3_bucket.lakehouse["silver"].id}/"
  silver_db        = "retail_lakehouse_${var.env}_silver"
  gold_db          = "retail_lakehouse_${var.env}_gold"
}

resource "aws_glue_job" "silver_purchases" {
  name              = "${var.project}-${var.env}-silver-purchases"
  role_arn          = aws_iam_role.glue_etl.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "${local.glue_script_base}/silver_purchases.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--SILVER_PATH"         = local.silver_path
    "--BRONZE_PATH"         = local.bronze_path
    "--SCRIPTS_PATH"        = local.scripts_path
    "--CATALOG_DB"          = local.silver_db
    "--enable-auto-scaling" = "true"
    "--datalake-formats"    = "iceberg"
    "--conf"                = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=${local.silver_path} --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }
}

resource "aws_glue_job" "silver_weather" {
  name              = "${var.project}-${var.env}-silver-weather"
  role_arn          = aws_iam_role.glue_etl.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "${local.glue_script_base}/silver_weather.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--SILVER_PATH"         = local.silver_path
    "--BRONZE_PATH"         = local.bronze_path
    "--CATALOG_DB"          = local.silver_db
    "--enable-auto-scaling" = "true"
    "--datalake-formats"    = "iceberg"
    "--conf"                = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=${local.silver_path} --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }
}

resource "aws_glue_job" "silver_reviews" {
  name              = "${var.project}-${var.env}-silver-reviews"
  role_arn          = aws_iam_role.glue_etl.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "${local.glue_script_base}/silver_reviews.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--SILVER_PATH"         = local.silver_path
    "--BRONZE_PATH"         = local.bronze_path
    "--CATALOG_DB"          = local.silver_db
    "--enable-auto-scaling" = "true"
    "--datalake-formats"    = "iceberg"
    "--conf"                = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=${local.silver_path} --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }
}

resource "aws_glue_job" "gold_weather_sales" {
  name              = "${var.project}-${var.env}-gold-weather-sales"
  role_arn          = aws_iam_role.glue_etl.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "${local.glue_script_base}/gold_weather_sales.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--SILVER_PATH"         = local.silver_path
    "--BRONZE_PATH"         = local.bronze_path
    "--SILVER_DB"           = local.silver_db
    "--GOLD_PATH"           = "s3://${aws_s3_bucket.lakehouse["gold"].id}/"
    "--CATALOG_DB"          = local.gold_db
    "--enable-auto-scaling" = "true"
    "--datalake-formats"    = "iceberg"
    "--conf"                = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=${local.silver_path} --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }
}
