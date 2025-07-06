# LocalStack File Processing Pipeline

This project creates a complete file processing pipeline using LocalStack and Terraform for local development.

## Architecture

```
S3 Input Bucket → SNS Topic → SQS Queue → Lambda Function → SNS Topic → S3 Output Bucket
                                                                ↓
                                                           SQS Queue
```

### Flow Description:
1. **File Upload**: A file is uploaded to the input S3 bucket
2. **S3 Event**: S3 triggers an SNS topic with the file path
3. **SNS to SQS**: SNS sends the message to a processing SQS queue
4. **Lambda Processing**: Lambda function is triggered by SQS messages
5. **File Processing**: Lambda downloads, processes, and saves the file to output bucket
6. **Success Notification**: Lambda publishes success/error message to another SNS topic
7. **Final Queue**: The processed SNS topic triggers a final SQS queue

## Prerequisites

- **LocalStack**: Install and run LocalStack
- **Terraform**: Install Terraform (>= 1.0)
- **AWS CLI**: Install AWS CLI for testing
- **Python**: Python 3.9+ (for Lambda function)

### Installation Commands:

```bash
# Install LocalStack
pip install localstack

# Install Terraform (example for macOS with Homebrew)
brew install terraform

# Install AWS CLI
pip install awscli
```

## Setup Instructions

### 1. Start LocalStack

```bash
localstack start
```

### 2. Configure AWS CLI for LocalStack

```bash
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set default.region us-east-1
```

### 3. Deploy the Infrastructure

#### Option A: Using the Deployment Script (Recommended)

```bash
chmod +x deploy.sh
./deploy.sh
```

#### Option B: Manual Deployment

```bash
# Create Lambda package
echo 'import json
import boto3
import os
from datetime import datetime

# ... (copy the lambda code from the artifact)
' > index.py

zip lambda_function.zip index.py

# Initialize and apply Terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### 4. Test the Pipeline

```bash
# Get the input bucket name
INPUT_BUCKET=$(terraform output -raw input_bucket_name)

# Create and upload a test file
echo "Hello, World! This is a test file." > test.txt
aws --endpoint-url=http://localhost:4566 s3 cp test.txt s3://$INPUT_BUCKET/

# Check if file was processed
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
aws --endpoint-url=http://localhost:4566 s3 ls s3://$OUTPUT_BUCKET/
```

## Testing and Monitoring

### Check SQS Queues

```bash
# Check processing queue
PROCESSING_QUEUE=$(terraform output -raw processing_queue_url)
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSING_QUEUE

# Check processed queue
PROCESSED_QUEUE=$(terraform output -raw processed_queue_url)
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSED_QUEUE
```

### Check Lambda Logs

```bash
# List log groups
aws --endpoint-url=http://localhost:4566 logs describe-log-groups

# Get specific log group
aws --endpoint-url=http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/file-processor-file-processor
```

### Check SNS Topics

```bash
# List SNS topics
aws --endpoint-url=http://localhost:4566 sns list-topics

# Get topic attributes
aws --endpoint-url=http://localhost:4566 sns get-topic-attributes --topic-arn $(terraform output -raw file_received_topic_arn)
```

## Customization

### Modifying the Lambda Function

1. Edit the `index.py` file in the Lambda function
2. Update the `process_file_content` function to implement your specific processing logic
3. Recreate the zip file and redeploy:

```bash
zip -r lambda_function.zip index.py
terraform apply -auto-approve
```

### Adding Environment Variables

Modify the `aws_lambda_function` resource in `main.tf`:

```hcl
environment {
  variables = {
    OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
    SNS_TOPIC_ARN = aws_sns_topic.file_processed.arn
    # Add your custom variables here
    CUSTOM_VAR = "value"
  }
}
```

### Changing Resource Names

Update the `project_name` variable in `main.tf` or pass it during deployment:

```bash
terraform apply -var="project_name=my-custom-pipeline"
```

## Troubleshooting

### Common Issues:

1. **LocalStack not running**: Ensure LocalStack is started with `localstack start`
2. **Lambda function not triggered**: Check SQS queue policies and Lambda event source mapping
3. **S3 notifications not working**: Verify SNS topic policies allow S3 to publish
4. **Permission errors**: Check IAM roles and policies

### Debug Commands:

```bash
# Check LocalStack services status
curl http://localhost:4566/health

# Check if resources exist
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 sns list-topics
aws --endpoint-url=http://localhost:4566 sqs list-queues
aws --endpoint-url=http://localhost:4566 lambda list-functions
```

## File Processing Logic

The Lambda function includes example processing logic that:
- Converts text files to uppercase
- Adds metadata headers
- Preserves binary files with processing metadata
- Handles errors gracefully

You can customize the `process_file_content` function for your specific needs.

## Resource Outputs

After deployment, Terraform provides these outputs:
- `input_bucket_name`: S3 bucket for input files
- `output_bucket_name`: S3 bucket for processed files
- `file_received_