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
