# ---------- IAM role for Redshift Spectrum ----------
resource "aws_iam_role" "redshift_spectrum" {
  name = "${var.project}-${var.env}-redshift-spectrum"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["redshift.amazonaws.com"] }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "redshift_spectrum" {
  role = aws_iam_role.redshift_spectrum.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.lakehouse["silver"].arn,
          "${aws_s3_bucket.lakehouse["silver"].arn}/*",
          aws_s3_bucket.lakehouse["gold"].arn,
          "${aws_s3_bucket.lakehouse["gold"].arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable",
          "glue:GetTables", "glue:GetPartition", "glue:GetPartitions",
          "glue:CreateDatabase", "glue:CreateTable", "glue:UpdateTable",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        Resource = aws_kms_key.lakehouse.arn
      }
    ]
  })
}

# ---------- Redshift Serverless namespace + workgroup ----------
resource "aws_redshiftserverless_namespace" "main" {
  namespace_name       = "${var.project}-${var.env}"
  admin_username       = "adminuser"
  admin_user_password  = var.redshift_admin_password
  db_name              = "dev"
  iam_roles            = [aws_iam_role.redshift_spectrum.arn]
  default_iam_role_arn = aws_iam_role.redshift_spectrum.arn
}

resource "aws_redshiftserverless_workgroup" "main" {
  namespace_name      = aws_redshiftserverless_namespace.main.namespace_name
  workgroup_name      = "${var.project}-${var.env}-wg"
  base_capacity       = 8
  publicly_accessible = false
  security_group_ids  = [aws_security_group.redshift.id]

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }
}

output "redshift_workgroup_endpoint" {
  value = aws_redshiftserverless_workgroup.main.endpoint
}
