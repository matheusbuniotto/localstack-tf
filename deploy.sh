#!/bin/bash

# LocalStack File Processing Pipeline Deployment Script

set -e

echo "🚀 Starting LocalStack File Processing Pipeline Deployment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if LocalStack is running
check_localstack() {
    print_status "Checking LocalStack status..."
    if ! curl -s http://localhost:4566/health > /dev/null; then
        print_error "LocalStack is not running. Please start LocalStack first."
        echo "Start LocalStack with: localstack start"
        exit 1
    fi
    print_status "LocalStack is running ✓"
}

# Create Lambda deployment package
create_lambda_package() {
    print_status "Creating Lambda deployment package..."
    
    # Create lambda function file
    cat > index.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

# Initialize AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

def handler(event, context):
    """
    Lambda function to process files from SQS messages
    """
    try:
        # Get environment variables
        output_bucket = os.environ['OUTPUT_BUCKET']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        
        # Process each record from SQS
        for record in event['Records']:
            # Parse the SQS message body (which contains SNS message)
            message_body = json.loads(record['body'])
            
            # Extract S3 event information from SNS message
            sns_message = json.loads(message_body['Message'])
            
            # Get S3 bucket and key from the event
            for s3_record in sns_message['Records']:
                bucket_name = s3_record['s3']['bucket']['name']
                object_key = s3_record['s3']['object']['key']
                
                print(f"Processing file: {object_key} from bucket: {bucket_name}")
                
                # Download the file from S3
                response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
                file_content = response['Body'].read()
                
                # Process the file (example: add timestamp and convert to uppercase)
                processed_content = process_file_content(file_content, object_key)
                
                # Generate output filename
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_key = f"processed_{timestamp}_{object_key}"
                
                # Save processed file to output bucket
                s3_client.put_object(
                    Bucket=output_bucket,
                    Key=output_key,
                    Body=processed_content
                )
                
                # Publish success message to SNS
                message = {
                    "status": "success",
                    "original_file": {
                        "bucket": bucket_name,
                        "key": object_key
                    },
                    "processed_file": {
                        "bucket": output_bucket,
                        "key": output_key
                    },
                    "processed_at": datetime.now().isoformat(),
                    "file_size": len(processed_content)
                }
                
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Message=json.dumps(message),
                    Subject=f"File Processed: {object_key}"
                )
                
                print(f"Successfully processed {object_key} -> {output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Files processed successfully')
        }
        
    except Exception as e:
        print(f"Error processing files: {str(e)}")
        
        # Publish error message to SNS
        error_message = {
            "status": "error",
            "error": str(e),
            "processed_at": datetime.now().isoformat()
        }
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(error_message),
                Subject="File Processing Error"
            )
        except Exception as sns_error:
            print(f"Failed to publish error to SNS: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing files: {str(e)}')
        }

def process_file_content(content, filename):
    """
    Process file content - customize this based on your needs
    """
    try:
        # Example processing: convert text to uppercase and add metadata
        text_content = content.decode('utf-8')
        
        processed_content = f"""
File Processing Report
=====================
Original File: {filename}
Processed At: {datetime.now().isoformat()}
Original Size: {len(content)} bytes

Processed Content:
{text_content.upper()}

Processing completed successfully.
"""
        
        return processed_content.encode('utf-8')
        
    except UnicodeDecodeError:
        # If it's not a text file, just add a processing header
        processed_content = f"""
Binary File Processing Report
============================
Original File: {filename}
Processed At: {datetime.now().isoformat()}
Original Size: {len(content)} bytes

[Binary content preserved]
"""
        
        return processed_content.encode('utf-8') + content
EOF

    # Create zip file
    zip -r lambda_function.zip index.py
    print_status "Lambda package created ✓"
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    print_status "Terraform initialized ✓"
}

# Apply Terraform configuration
apply_terraform() {
    print_status "Applying Terraform configuration..."
    terraform plan
    terraform apply -auto-approve
    print_status "Infrastructure deployed ✓"
}

# Test the pipeline
test_pipeline() {
    print_status "Testing the pipeline..."
    
    # Create a test file
    echo "Hello, this is a test file for the processing pipeline!" > test_file.txt
    
    # Get bucket name from terraform output
    INPUT_BUCKET=$(terraform output -raw input_bucket_name)
    
    # Upload test file to S3
    aws --endpoint-url=http://localhost:4566 s3 cp test_file.txt s3://$INPUT_BUCKET/
    
    print_status "Test file uploaded to $INPUT_BUCKET"
    print_status "Pipeline should now process the file automatically..."
    
    # Clean up test file
    rm test_file.txt
}

# Show useful information
show_info() {
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📊 Infrastructure Overview:"
    echo "=========================="
    
    INPUT_BUCKET=$(terraform output -raw input_bucket_name)
    OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
    PROCESSING_QUEUE=$(terraform output -raw processing_queue_url)
    PROCESSED_QUEUE=$(terraform output -raw processed_queue_url)
    
    echo "Input Bucket: $INPUT_BUCKET"
    echo "Output Bucket: $OUTPUT_BUCKET"
    echo "Processing Queue: $PROCESSING_QUEUE"
    echo "Processed Queue: $PROCESSED_QUEUE"
    echo ""
    
    echo "🧪 Testing Commands:"
    echo "==================="
    echo "# Upload a file to trigger the pipeline:"
    echo "aws --endpoint-url=http://localhost:4566 s3 cp your_file.txt s3://$INPUT_BUCKET/"
    echo ""
    echo "# Check messages in processing queue:"
    echo "aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSING_QUEUE"
    echo ""
    echo "# Check messages in processed queue:"
    echo "aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSED_QUEUE"
    echo ""
    echo "# List files in output bucket:"
    echo "aws --endpoint-url=http://localhost:4566 s3 ls s3://$OUTPUT_BUCKET/"
    echo ""
    echo "# Check Lambda logs:"
    echo "aws --endpoint-url=http://localhost:4566 logs describe-log-groups"
}

# Main execution
main() {
    check_localstack
    create_lambda_package
    init_terraform
    apply_terraform
    test_pipeline
    show_info
}

# Run main function
main