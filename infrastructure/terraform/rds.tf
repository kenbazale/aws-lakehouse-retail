# ============================================================
# RDS PostgreSQL — Source for DMS CDC
# ============================================================

# --- Subnet group: reuse the two private subnets DMS already uses ---
resource "aws_db_subnet_group" "retail" {
  name = "${var.project}-${var.env}-rds-subnet"
  subnet_ids = var.private_subnet_ids
}

# --- Security group: allow DMS SG to reach Postgres ---
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds"
  description = "RDS PostgreSQL for retail-lakehouse CDC source"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from DMS replication instance"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Secrets Manager: master password + dms_user password ---
resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${var.project}-${var.env}-rds-master"
  recovery_window_in_days = 0 # dev: delete immediately, no 30-day cooldown
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username = "retailadmin"
    password = var.rds_master_password
    database = "retail"
  })
}

# --- Parameter group: mandatory for DMS logical replication ---
resource "aws_db_parameter_group" "retail" {
  name   = "${var.project}-${var.env}-pg15-logical"
  family = "postgres15"

  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

# --- The RDS instance ---
resource "aws_db_instance" "retail" {
  identifier        = "${var.project}-${var.env}-retail"
  engine            = "postgres"
  engine_version    = "15.7"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.lakehouse.arn

  db_name  = "retail"
  username = "retailadmin"
  password = var.rds_master_password

  db_subnet_group_name   = aws_db_subnet_group.retail.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.retail.name

  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 1
  skip_final_snapshot     = true  # dev only — prod: set false
  deletion_protection     = false # dev only — prod: set true
  apply_immediately       = true

  performance_insights_enabled = false
}

output "rds_endpoint" {
  value = aws_db_instance.retail.address
}

output "rds_port" {
  value = aws_db_instance.retail.port
}