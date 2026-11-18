# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "s3_processor" {
  filename         = "${path.module}/../lambda/processor.zip"
  function_name    = "${var.project_name}-s3-log-processor"
  role             = aws_iam_role.lambda.arn
  handler          = "processor.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/../lambda/processor.zip")
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      PROJECT = var.project_name
    }
  }

  tags = {
    Name    = "${var.project_name}-lambda"
    Project = var.project_name
  }
}

# Allow S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.logs.arn
}

# S3 Bucket Notification Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "logs/"
    filter_suffix       = ".tar.gz"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
