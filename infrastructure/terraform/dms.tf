resource "aws_security_group" "dms" {
  name        = "${var.project}-${var.env}-dms"
  description = "DMS replication instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.project}-${var.env}-dms-subnet"
  replication_subnet_group_description = "DMS subnet group"
  subnet_ids                           = var.private_subnet_ids
}

resource "aws_dms_replication_instance" "main" {
  replication_instance_id     = "${var.project}-${var.env}-dms"
  replication_instance_class  = var.dms_instance_class
  allocated_storage           = var.dms_allocated_storage
  multi_az                    = var.dms_multi_az
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  publicly_accessible         = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids      = [aws_security_group.dms.id]
}

resource "aws_dms_endpoint" "postgres_source" {
  endpoint_id   = "${var.project}-${var.env}-pg-source"
  endpoint_type = "source"
  engine_name   = "postgres"
  server_name   = aws_db_instance.retail.address        # ← CHANGED
  port          = 5432
  database_name = "retail"
  username      = "dms_user"
  password      = var.dms_password
  ssl_mode      = "require"
}

resource "aws_dms_endpoint" "s3_target" {
  endpoint_id   = "${var.project}-${var.env}-s3-bronze"
  endpoint_type = "target"
  engine_name   = "s3"

  s3_settings {
    bucket_name             = aws_s3_bucket.lakehouse["bronze"].id
    bucket_folder           = "cdc/purchases"
    service_access_role_arn = aws_iam_role.dms_s3.arn
    data_format             = "parquet"
    parquet_version         = "parquet-2-0"
    compression_type        = "GZIP"
    cdc_path                = "cdc"
    include_op_for_full_load = true
    date_partition_enabled  = true
    date_partition_sequence = "YYYYMMDDHH"
    # Provider otherwise sends "", which DMS rejects on CreateReplicationTask.
    timestamp_column_name = "_dms_timestamp"
  }

  depends_on = [aws_iam_role_policy.dms_s3]
}

resource "aws_dms_replication_task" "purchases_cdc" {
  replication_task_id       = "${var.project}-${var.env}-purchases-cdc"
  migration_type            = "full-load-and-cdc"
  replication_instance_arn  = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.postgres_source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.s3_target.endpoint_arn
  table_mappings            = file("${path.module}/dms/table_mappings.json")
  replication_task_settings = file("${path.module}/dms/task_settings.json")
}
