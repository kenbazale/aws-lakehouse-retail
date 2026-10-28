# ---------- IAM: Lambda execution role ----------
resource "aws_iam_role" "weather_poller" {
  name = "${var.project}-${var.env}-weather-poller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "weather_poller" {
  role = aws_iam_role.weather_poller.id

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
        Resource = "${aws_s3_bucket.lakehouse["bronze"].arn}/raw/weather/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Encrypt"]
        Resource = aws_kms_key.lakehouse.arn
      }
    ]
  })
}

# ---------- Lambda function ----------
resource "aws_lambda_function" "weather_poller" {
  function_name = "${var.project}-${var.env}-weather-poller"
  role          = aws_iam_role.weather_poller.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 512

  filename         = "${path.module}/../../ingestion/lambda/weather_poller/weather_poller.zip"
  source_code_hash = filebase64sha256("${path.module}/../../ingestion/lambda/weather_poller/weather_poller.zip")

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.lakehouse["bronze"].id
      API_BASE      = "https://api.open-meteo.com/v1/forecast"
    }
  }

  depends_on = [aws_cloudwatch_log_group.weather_poller]
}

resource "aws_cloudwatch_log_group" "weather_poller" {
  name              = "/aws/lambda/${var.project}-${var.env}-weather-poller"
  retention_in_days = 14
}

# ---------- EventBridge hourly schedule ----------
resource "aws_cloudwatch_event_rule" "weather_schedule" {
  name                = "${var.project}-${var.env}-weather-hourly"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "weather_target" {
  rule      = aws_cloudwatch_event_rule.weather_schedule.name
  target_id = "weather-lambda"
  arn       = aws_lambda_function.weather_poller.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_poller.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_schedule.arn
}

output "weather_poller_function_name" {
  value = aws_lambda_function.weather_poller.function_name
}
