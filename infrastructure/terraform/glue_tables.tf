locals {
  bronze_bucket = aws_s3_bucket.lakehouse["bronze"].id
  bronze_db     = aws_glue_catalog_database.bronze.name
}

# ---------------------------------------------------------------
# bronze_purchases_full_load
# ---------------------------------------------------------------
resource "aws_glue_catalog_table" "bronze_purchases_full_load" {
  name          = "bronze_purchases_full_load"
  database_name = local.bronze_db
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "parquet.compression" = "GZIP"
    "classification"      = "parquet"
    "typeOfData"          = "file"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/cdc/purchases/public/purchases/load/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "op"
      type = "string"
    }
    columns {
      name = "_dms_timestamp"
      type = "string"
    }
    columns {
      name = "purchase_id"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "int"
    }
    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "amount"
      type = "decimal(18,2)"
    }
    columns {
      name = "currency"
      type = "string"
    }
    columns {
      name = "purchase_ts"
      type = "timestamp"
    }
  }
}

# ---------------------------------------------------------------
# bronze_purchases_cdc (partitioned, with partition projection)
# ---------------------------------------------------------------
resource "aws_glue_catalog_table" "bronze_purchases_cdc" {
  name          = "bronze_purchases_cdc"
  database_name = local.bronze_db
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "parquet.compression" = "GZIP"
    "classification"      = "parquet"
    "typeOfData"          = "file"

    # --- partition projection (avoids MSCK REPAIR) ---
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2030"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "1,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "1,31"
    "projection.day.digits"     = "2"
    "projection.hour.type"      = "integer"
    "projection.hour.range"     = "0,23"
    "projection.hour.digits"    = "2"
    "storage.location.template" = "s3://${local.bronze_bucket}/cdc/purchases/public/purchases/$${year}/$${month}/$${day}/$${hour}/"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/cdc/purchases/public/purchases/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "op"
      type = "string"
    }
    columns {
      name = "_dms_timestamp"
      type = "string"
    }
    columns {
      name = "purchase_id"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "int"
    }
    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "amount"
      type = "decimal(18,2)"
    }
    columns {
      name = "currency"
      type = "string"
    }
    columns {
      name = "purchase_ts"
      type = "timestamp"
    }
  }
}

# ---------------------------------------------------------------
# bronze_customers
# ---------------------------------------------------------------
resource "aws_glue_catalog_table" "bronze_customers" {
  name          = "bronze_customers"
  database_name = local.bronze_db
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "parquet.compression" = "GZIP"
    "classification"      = "parquet"
    "typeOfData"          = "file"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/cdc/purchases/public/customers/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "op"
      type = "string"
    }
    columns {
      name = "_dms_timestamp"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "int"
    }
    columns {
      name = "email"
      type = "string"
    }
    columns {
      name = "full_name"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "created_at"
      type = "timestamp"
    }
  }
}
