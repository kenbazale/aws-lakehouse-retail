# ---------- IAM ----------
resource "aws_iam_role" "reviews_poller" {
  name = "${var.project}-${var.env}-reviews-poller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "reviews_poller" {
  role = aws_iam_role.reviews_poller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = "${aws_s3_bucket.lakehouse["bronze"].arn}/raw/reviews/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Encrypt"]
        Resource = aws_kms_key.lakehouse.arn
      }
    ]
  })
}

# ---------- Lambda ----------
resource "aws_lambda_function" "reviews_poller" {
  function_name = "${var.project}-${var.env}-reviews-poller"
  role          = aws_iam_role.reviews_poller.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/../../ingestion/lambda/reviews_poller/reviews_poller.zip"
  source_code_hash = filebase64sha256("${path.module}/../../ingestion/lambda/reviews_poller/reviews_poller.zip")

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.lakehouse["bronze"].id
    }
  }

  depends_on = [aws_cloudwatch_log_group.reviews_poller]
}

resource "aws_cloudwatch_log_group" "reviews_poller" {
  name              = "/aws/lambda/${var.project}-${var.env}-reviews-poller"
  retention_in_days = 14
}

# ---------- Schedule: every 15 minutes ----------
resource "aws_cloudwatch_event_rule" "reviews_schedule" {
  name                = "${var.project}-${var.env}-reviews-15min"
  schedule_expression = "rate(15 minutes)"
}

resource "aws_cloudwatch_event_target" "reviews_target" {
  rule      = aws_cloudwatch_event_rule.reviews_schedule.name
  target_id = "reviews-lambda"
  arn       = aws_lambda_function.reviews_poller.arn
}

resource "aws_lambda_permission" "allow_eventbridge_reviews" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reviews_poller.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reviews_schedule.arn
}

output "reviews_poller_function_name" {
  value = aws_lambda_function.reviews_poller.function_name
}
