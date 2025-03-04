resource "aws_iam_role" "greeting_lambda_execution_role" {
  name = "greeting_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_policy" "greeting_lambda_s3_policy" {
  name        = "greeting_lambda_s3_policy"
  description = "Grants access to source and destination buckets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["s3:GetObject"],
        Effect = "Allow",
        Resource = [
          "${var.src_bucket_arn}/*"
        ]
        }, {
        Action = ["s3:PutObject"],
        Effect = "Allow",
        Resource = [
          "${var.dst_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "greeting_lambda_s3_policy_attachment" {
  policy_arn = aws_iam_policy.greeting_lambda_s3_policy.arn
  role       = aws_iam_role.greeting_lambda_execution_role.name
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../../../app/index.mjs"
  output_path = "../../../app/lambda.zip"
 # source_file = "${path.modules}/../../app/index.mjs"
  # output_path = "lambda.zip"
}

resource "aws_lambda_function" "greeting_lambda" {
  function_name = "greeting_lambda"

  handler     = "index.handler"
  runtime     = "nodejs18.x"
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.greeting_lambda_execution_role.arn

  environment {
    variables = {
      SRC_BUCKET = var.src_bucket_id,
      DST_BUCKET = var.dst_bucket_id
    }
  }

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    environment : var.tag_environment
  }
}

# SQS Event Source Mapping integration
resource "aws_iam_policy" "greeting_lambda_sqs_policy" {
  name        = "greeting_lambda_sqs_policy"
  description = "Grants access to read messages from SQS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMEssage", "sqs:GetQueueAttributes"],
        Effect   = "Allow",
        Resource = [var.greeting_queue_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "greeting_lambda_sqs_policy_attachment" {
  policy_arn = aws_iam_policy.greeting_lambda_sqs_policy.arn
  role       = aws_iam_role.greeting_lambda_execution_role.name
}

resource "aws_lambda_event_source_mapping" "greeting_sqs_mapping" {
  event_source_arn = var.greeting_queue_arn
  function_name    = aws_lambda_function.greeting_lambda.function_name
  batch_size       = 1

  depends_on = [aws_iam_role_policy_attachment.greeting_lambda_sqs_policy_attachment]
}

# Creates an IAM policy that allows the Lambda function to write logs to CloudWatch.
resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "LambdaCloudWatchPolicy"
  description = "Allows Lambda to write logs to CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:eu-north-1:084828605119:log-group:${aws_cloudwatch_log_group.lambda-log-group.name}:*"
      }
    ]
  })
}

# Attaches the lambda_cloudwatch_policy to the greeting_lambda_execution_role for CloudWatch logging permissions.
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attach" {
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
  role       = aws_iam_role.greeting_lambda_execution_role.name
}

# Creates a CloudWatch log group to store logs generated by the Lambda function and retains logs for 14 days.
resource "aws_cloudwatch_log_group" "lambda-log-group" {
  name              = "/aws/lambda/${aws_lambda_function.greeting_lambda.function_name}"
  retention_in_days = 14
}
