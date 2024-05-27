provider "aws" {
  region = "us-east-1"
}

# S3 bucket for storing uploaded files
resource "aws_s3_bucket" "file_storage" {
  bucket = "lambda-api-upload100"
}

# Disable public access block
resource "aws_s3_bucket_public_access_block" "file_storage_public_access" {
  bucket                  = aws_s3_bucket.file_storage.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda to access S3 and manage bucket policies
resource "aws_iam_policy" "lambda_s3_access_policy" {
  name        = "lambda_s3_access_policy"
  description = "Policy for Lambda to access S3 and manage bucket policies"

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:PutObject", "s3:GetObject", "s3:PutBucketPolicy"],
        Effect   = "Allow",
        Resource = [
          "${aws_s3_bucket.file_storage.arn}",
          "${aws_s3_bucket.file_storage.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_role_create_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_s3_access_policy.arn
}

# Lambda function
resource "aws_lambda_function" "file_upload_lambda" {
  function_name    = "FileUploadLambda"
  handler          = "lambda.lambda_handler"
  runtime          = "python3.8"
  role             = aws_iam_role.lambda_execution_role.arn
  filename         = "lambda.zip"  # Path to your deployment package
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.file_storage.bucket
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "file_upload_api" {
  name        = "FileUploadAPI"
  description = "API for file upload through Lambda"
  binary_media_types = ["application/pdf"]  # Add binary media type
}

# API Gateway resource
resource "aws_api_gateway_resource" "file_upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.file_upload_api.id
  parent_id   = aws_api_gateway_rest_api.file_upload_api.root_resource_id
  path_part   = "upload"
}

# API Gateway method
resource "aws_api_gateway_method" "file_upload_method" {
  rest_api_id   = aws_api_gateway_rest_api.file_upload_api.id
  resource_id   = aws_api_gateway_resource.file_upload_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Lambda integration
resource "aws_api_gateway_integration" "file_upload_integration" {
  rest_api_id             = aws_api_gateway_rest_api.file_upload_api.id
  resource_id             = aws_api_gateway_resource.file_upload_resource.id
  http_method             = aws_api_gateway_method.file_upload_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.file_upload_lambda.invoke_arn
  content_handling        = "CONVERT_TO_BINARY"

  request_templates = {
    "application/pdf" = <<EOF
{

    "content": "$input.body"

}
EOF
  }
}

# API Gateway Lambda permission
resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.file_upload_api.execution_arn}/*/*"
}

# IAM policy for Lambda to access CloudWatch Logs
resource "aws_iam_policy" "lambda_cloudwatch_logs_policy" {
  name        = "lambda_cloudwatch_logs_policy"
  description = "Policy for Lambda to write logs to CloudWatch Logs"

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      Resource  = "arn:aws:logs:*:*:*"
    }]
  })
}

# Attach CloudWatch Logs policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_logs_policy.arn
}

# S3 bucket policy for public read access
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.file_storage.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.file_storage.arn}/*"
      }
    ]
  })
}
