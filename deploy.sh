#!/bin/bash

# Script de Implantação para o Pipeline de Processamento de Arquivos no LocalStack

set -e

echo "🚀 Iniciando a implantação do Pipeline de Processamento de Arquivos no LocalStack"

# Cores para o output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sem Cor

# Função para imprimir output colorido
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica se o LocalStack está em execução
check_localstack() {
    print_status "Verificando o status do LocalStack..."
    if ! curl -s http://localhost:4566/health > /dev/null; then
        print_error "O LocalStack não está em execução. Por favor, inicie o LocalStack primeiro."
        echo "Inicie o LocalStack com: localstack start"
        exit 1
    fi
    print_status "LocalStack está em execução ✓"
}

# Cria o pacote de implantação da Lambda
create_lambda_package() {
    print_status "Criando o pacote de implantação da Lambda..."
    
    # Cria o arquivo da função lambda (index.py)
    cat > index.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

# Inicializa os clientes AWS
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
secrets_manager_client = boto3.client('secretsmanager')

def get_secret(secret_arn):
    """
    Função para buscar um segredo do AWS Secrets Manager.
    """
    try:
        response = secrets_manager_client.get_secret_value(SecretId=secret_arn)
        return response['SecretString']
    except Exception as e:
        print(f"Erro ao buscar o segredo: {str(e)}")
        raise e

def handler(event, context):
    """
    Função Lambda para processar arquivos a partir de mensagens SQS.
    """
    try:
        # Obtém as variáveis de ambiente
        output_bucket = os.environ['OUTPUT_BUCKET']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        secret_arn = os.environ['SECRET_ARN']
        
        # Busca o segredo
        api_key = get_secret(secret_arn)
        
        # Processa cada registro do SQS
        for record in event['Records']:
            message_body = json.loads(record['body'])
            sns_message = json.loads(message_body['Message'])
            
            for s3_record in sns_message['Records']:
                bucket_name = s3_record['s3']['bucket']['name']
                object_key = s3_record['s3']['object']['key']
                
                print(f"Processando arquivo: {object_key} do bucket: {bucket_name}")
                
                response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
                file_content = response['Body'].read()
                
                # Processa o conteúdo do arquivo, passando a chave da API
                processed_content = process_file_content(file_content, object_key, api_key)
                
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_key = f"processed_{timestamp}_{object_key}"
                
                s3_client.put_object(
                    Bucket=output_bucket,
                    Key=output_key,
                    Body=processed_content
                )
                
                message = {
                    "status": "success",
                    "original_file": {"bucket": bucket_name, "key": object_key},
                    "processed_file": {"bucket": output_bucket, "key": output_key},
                    "processed_at": datetime.now().isoformat(),
                    "file_size": len(processed_content)
                }
                
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Message=json.dumps(message),
                    Subject=f"Arquivo Processado: {object_key}"
                )
                
                print(f"Processado com sucesso {object_key} -> {output_key}")
        
        return {'statusCode': 200, 'body': json.dumps('Arquivos processados com sucesso')}
        
    except Exception as e:
        print(f"Erro ao processar arquivos: {str(e)}")
        error_message = {
            "status": "error",
            "error": str(e),
            "processed_at": datetime.now().isoformat()
        }
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps(error_message),
                Subject="Erro no Processamento de Arquivos"
            )
        except Exception as sns_error:
            print(f"Falha ao publicar erro no SNS: {str(sns_error)}")
        
        return {'statusCode': 500, 'body': json.dumps(f'Erro ao processar arquivos: {str(e)}')}

def process_file_content(content, filename, api_key):
    """
    Processa o conteúdo do arquivo - personalize conforme suas necessidades.
    """
    try:
        text_content = content.decode('utf-8')
        processed_content = f"""
Relatório de Processamento de Arquivo
====================================
Arquivo Original: {filename}
Processado Em: {datetime.now().isoformat()}
Tamanho Original: {len(content)} bytes
Segredo Utilizado (API Key): {api_key}

Conteúdo Processado:
{text_content.upper()}

Processamento concluído com sucesso.
"""
        return processed_content.encode('utf-8')
        
    except UnicodeDecodeError:
        processed_content = f"""
Relatório de Processamento de Arquivo Binário
===========================================
Arquivo Original: {filename}
Processado Em: {datetime.now().isoformat()}
Tamanho Original: {len(content)} bytes
Segredo Utilizado (API Key): {api_key}

[Conteúdo binário preservado]
"""
        return processed_content.encode('utf-8') + content
EOF

    # Cria o arquivo zip
    zip -r lambda_function.zip index.py
    print_status "Pacote Lambda criado ✓"
}

# Inicializa o Terraform
init_terraform() {
    print_status "Inicializando o Terraform..."
    terraform init
    print_status "Terraform inicializado ✓"
}

# Aplica a configuração do Terraform
apply_terraform() {
    print_status "Aplicando a configuração do Terraform..."
    terraform plan
    terraform apply -auto-approve
    print_status "Infraestrutura implantada ✓"
}

# Testa o pipeline
test_pipeline() {
    print_status "Testando o pipeline..."
    
    echo "Olá, este é um arquivo de teste para o pipeline de processamento!" > test_file.txt
    
    INPUT_BUCKET=$(terraform output -raw input_bucket_name)
    
    aws --endpoint-url=http://localhost:4566 s3 cp test_file.txt s3://$INPUT_BUCKET/
    
    print_status "Arquivo de teste enviado para $INPUT_BUCKET"
    print_status "O pipeline agora deve processar o arquivo automaticamente..."
    
    rm test_file.txt
}

# Exibe informações úteis
show_info() {
    echo ""
    echo "🎉 Implantação concluída com sucesso!"
    echo ""
    echo "📊 Visão Geral da Infraestrutura:"
    echo "================================"
    
    INPUT_BUCKET=$(terraform output -raw input_bucket_name)
    OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
    PROCESSING_QUEUE=$(terraform output -raw processing_queue_url)
    PROCESSED_QUEUE=$(terraform output -raw processed_queue_url)
    SECRET_ARN=$(terraform output -raw secret_arn)
    
    echo "Bucket de Entrada: $INPUT_BUCKET"
    echo "Bucket de Saída: $OUTPUT_BUCKET"
    echo "Fila de Processamento: $PROCESSING_QUEUE"
    echo "Fila Processada: $PROCESSED_QUEUE"
    echo "ARN do Segredo: $SECRET_ARN"
    echo ""
    
    echo "🧪 Comandos de Teste:"
    echo "===================="
    echo "# Enviar um arquivo para acionar o pipeline:"
    echo "aws --endpoint-url=http://localhost:4566 s3 cp seu_arquivo.txt s3://$INPUT_BUCKET/"
    echo ""
    echo "# Ler o valor do segredo no Secrets Manager:"
    echo "aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value --secret-id $SECRET_ARN"
    echo ""
    echo "# Listar arquivos no bucket de saída:"
    echo "aws --endpoint-url=http://localhost:4566 s3 ls s3://$OUTPUT_BUCKET/"
    echo ""
}

# Execução principal
main() {
    check_localstack
    create_lambda_package
    init_terraform
    apply_terraform
    test_pipeline
    show_info
}

# Executa a função principal
main