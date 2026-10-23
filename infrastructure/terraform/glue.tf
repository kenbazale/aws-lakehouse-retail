# ---------- Glue Catalog: databases ----------
resource "aws_glue_catalog_database" "bronze" {
  name        = "retail_lakehouse_${var.env}_bronze"
  description = "Raw ingestion layer — Parquet as landed from DMS/Lambda"
}

resource "aws_glue_catalog_database" "silver" {
  name        = "retail_lakehouse_${var.env}_silver"
  description = "Cleaned, conformed Iceberg tables"
}

resource "aws_glue_catalog_database" "gold" {
  name        = "retail_lakehouse_${var.env}_gold"
  description = "Business-level aggregates"
}

# ---------- Glue Crawler IAM ----------
resource "aws_iam_role" "glue_crawler" {
  name = "${var.project}-${var.env}-glue-crawler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_crawler_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_crawler_s3" {
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.lakehouse["bronze"].arn,
          "${aws_s3_bucket.lakehouse["bronze"].arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.lakehouse.arn
      }
    ]
  })
}

