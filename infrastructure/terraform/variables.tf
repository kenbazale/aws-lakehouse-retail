variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "lakehouse_buckets" {
  type    = list(string)
  default = ["bronze", "silver", "gold", "scripts", "logs", "quarantine"]
}

variable "vpc_id" {
  type        = string
  description = "VPC for the DMS replication instance and security group"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "At least two subnet IDs in different AZs for the DMS subnet group"
}

variable "dms_password" {
  type        = string
  sensitive   = true
  description = "Password for the dms_user on the source database"
}

variable "rds_master_password" {
  type        = string
  sensitive   = true
  description = "Master password for the RDS PostgreSQL instance"
}

variable "redshift_admin_password" {
  type        = string
  sensitive   = true
  description = "Administrator password for the Redshift Serverless namespace"
}

variable "dms_instance_class" {
  type    = string
  default = "dms.t3.medium"
}

variable "dms_allocated_storage" {
  type    = number
  default = 50
}

variable "dms_multi_az" {
  type    = bool
  default = false
}