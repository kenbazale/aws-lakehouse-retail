output "bronze_bucket" { value = aws_s3_bucket.lakehouse["bronze"].id }
output "silver_bucket" { value = aws_s3_bucket.lakehouse["silver"].id }
output "gold_bucket"   { value = aws_s3_bucket.lakehouse["gold"].id }
output "scripts_bucket" { value = aws_s3_bucket.lakehouse["scripts"].id }
output "logs_bucket"   { value = aws_s3_bucket.lakehouse["logs"].id }
output "kms_key_arn"   { value = aws_kms_key.lakehouse.arn }