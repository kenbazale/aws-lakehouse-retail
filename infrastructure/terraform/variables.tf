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

variable "rds_endpoint" {
  type        = string
  description = "PostgreSQL hostname (RDS endpoint) used as the DMS source"
}

variable "dms_password" {
  type        = string
  sensitive   = true
  description = "Password for the dms_user on the source database"
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