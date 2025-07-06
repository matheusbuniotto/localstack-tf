# LocalStack Terraform Configuration
# File Processing Pipeline: S3 -> SNS -> SQS -> Lambda -> SNS -> S3 -> SQS

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure AWS Provider for LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://127.0.0.1:4566"
    sns      = "http://127.0.0.1:4566"
    sqs      = "http://127.0.0.1:4566"
    lambda   = "http://127.0.0.1:4566"
    iam      = "http://127.0.0.1:4566"
  }
}

# Variables
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "file-processor"
}

# S3 Buckets
resource "aws_s3_bucket" "input_bucket" {
  bucket = "${var.project_name}-input-bucket"
}

resource "aws_s3_bucket" "output_bucket" {
  bucket = "${var.project_name}-output-bucket"
}

# SNS Topics
resource "aws_sns_topic" "file_received" {
  name = "${var.project_name}-file-received"
}

resource "aws_sns_topic" "file_processed" {
  name = "${var.project_name}-file-processed"
}

# SQS Queues
resource "aws_sqs_queue" "file_processing_queue" {
  name = "${var.project_name}-file-processing-queue"
}

resource "aws_sqs_queue" "file_processed_queue" {
  name = "${var.project_name}-file-processed-queue"
}

# Dead Letter Queues
resource "aws_sqs_queue" "processing_dlq" {
  name = "${var.project_name}-processing-dlq"
}

resource "aws_sqs_queue" "processed_dlq" {
  name = "${var.project_name}-processed-dlq"
}

# Update SQS queues with DLQ configuration
resource "aws_sqs_queue_redrive_policy" "file_processing_queue_redrive" {
  queue_url = aws_sqs_queue.file_processing_queue.url
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_policy" "file_processed_queue_redrive" {
  queue_url = aws_sqs_queue.file_processed_queue.url
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processed_dlq.arn
    maxReceiveCount     = 3
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
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

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.input_bucket.arn}/*",
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.file_processing_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.file_processed.arn
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "file_processor" {
  filename         = "lambda_function.zip"
  function_name    = "${var.project_name}-file-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
      SNS_TOPIC_ARN = aws_sns_topic.file_processed.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

# Lambda Event Source Mapping (SQS -> Lambda)
resource "aws_lambda_event_source_mapping" "sqs_lambda_trigger" {
  event_source_arn = aws_sqs_queue.file_processing_queue.arn
  function_name    = aws_lambda_function.file_processor.arn
  batch_size       = 1
}

# SNS Subscription (SNS -> SQS for file processing)
resource "aws_sns_topic_subscription" "file_received_to_sqs" {
  topic_arn = aws_sns_topic.file_received.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.file_processing_queue.arn
}

# SNS Subscription (SNS -> SQS for processed files)
resource "aws_sns_topic_subscription" "file_processed_to_sqs" {
  topic_arn = aws_sns_topic.file_processed.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.file_processed_queue.arn
}

# SQS Queue Policy (Allow SNS to send messages)
resource "aws_sqs_queue_policy" "file_processing_queue_policy" {
  queue_url = aws_sqs_queue.file_processing_queue.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.file_processing_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.file_received.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "file_processed_queue_policy" {
  queue_url = aws_sqs_queue.file_processed_queue.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.file_processed_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.file_processed.arn
          }
        }
      }
    ]
  })
}

# S3 Bucket Notification (S3 -> SNS)
resource "aws_s3_bucket_notification" "input_bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  topic {
    topic_arn     = aws_sns_topic.file_received.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ""
  }

  depends_on = [aws_sns_topic_policy.file_received_policy]
}

# SNS Topic Policy (Allow S3 to publish)
resource "aws_sns_topic_policy" "file_received_policy" {
  arn = aws_sns_topic.file_received.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.file_received.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.input_bucket.arn
          }
        }
      }
    ]
  })
}

# Outputs
output "input_bucket_name" {
  description = "Name of the input S3 bucket"
  value       = aws_s3_bucket.input_bucket.bucket
}

output "output_bucket_name" {
  description = "Name of the output S3 bucket"
  value       = aws_s3_bucket.output_bucket.bucket
}

output "file_received_topic_arn" {
  description = "ARN of the file received SNS topic"
  value       = aws_sns_topic.file_received.arn
}

output "file_processed_topic_arn" {
  description = "ARN of the file processed SNS topic"
  value       = aws_sns_topic.file_processed.arn
}

output "processing_queue_url" {
  description = "URL of the file processing SQS queue"
  value       = aws_sqs_queue.file_processing_queue.url
}

output "processed_queue_url" {
  description = "URL of the file processed SQS queue"
  value       = aws_sqs_queue.file_processed_queue.url
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.file_processor.function_name
}