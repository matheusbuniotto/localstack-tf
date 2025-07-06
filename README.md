# Pipeline de Processamento de Arquivos com LocalStack

Este projeto cria um pipeline completo de processamento de arquivos usando LocalStack e Terraform para desenvolvimento local.

## Arquitetura

```
S3 Input Bucket → SNS Topic → SQS Queue → Lambda Function → SNS Topic → S3 Output Bucket
                                                                ↓
                                                           SQS Queue
```

### Descrição do Fluxo:
1. **Upload de Arquivo**: Um arquivo é enviado para o bucket S3 de entrada
2. **Evento S3**: O S3 aciona um tópico SNS com o caminho do arquivo
3. **SNS para SQS**: O SNS envia a mensagem para uma fila SQS de processamento
4. **Processamento Lambda**: A função Lambda é acionada pelas mensagens SQS
5. **Processamento de Arquivo**: A Lambda baixa, processa e salva o arquivo no bucket de saída
6. **Notificação de Sucesso**: A Lambda publica uma mensagem de sucesso/erro em outro tópico SNS
7. **Fila Final**: O tópico SNS processado aciona uma fila SQS final

## Pré-requisitos

- **LocalStack**: Instale e execute o LocalStack
- **Terraform**: Instale o Terraform (>= 1.0)
- **AWS CLI**: Instale o AWS CLI para testes
- **Python**: Python 3.9+ (para função Lambda)

### Comandos de Instalação:

```bash
# Instalar LocalStack
pip install localstack

# Instalar Terraform (exemplo para macOS com Homebrew)
brew install terraform

# Instalar AWS CLI
pip install awscli
```

## Instruções de Configuração

### 1. Iniciar o LocalStack

```bash
localstack start
```

### 2. Configurar AWS CLI para LocalStack

```bash
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set default.region us-east-1
```

### 3. Implantar a Infraestrutura

#### Opção A: Usando o Script de Implantação (Recomendado)

```bash
chmod +x deploy.sh
./deploy.sh
```

#### Opção B: Implantação Manual

```bash
# Criar pacote Lambda
echo 'import json
import boto3
import os
from datetime import datetime
....
' > index.py

zip lambda_function.zip index.py

# Inicializar e aplicar Terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### 4. Testar o Pipeline

```bash
# Obter o nome do bucket de entrada
INPUT_BUCKET=$(terraform output -raw input_bucket_name)

# Criar e enviar um arquivo de teste
echo "Hello, World! This is a test file." > test.txt
aws --endpoint-url=http://127.0.0.1:4566 s3 cp test.txt s3://$INPUT_BUCKET/

# Verificar se o arquivo foi processado
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
aws --endpoint-url=http://127.0.0.1:4566 s3 ls s3://$OUTPUT_BUCKET/
```

## Testes e Monitoramento

### Verificar Filas SQS

```bash
# Verificar fila de processamento
PROCESSING_QUEUE=$(terraform output -raw processing_queue_url)
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSING_QUEUE

# Verificar fila processada
PROCESSED_QUEUE=$(terraform output -raw processed_queue_url)
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSED_QUEUE
```

### Verificar Logs da Lambda

```bash
# Listar grupos de logs
aws --endpoint-url=http://localhost:4566 logs describe-log-groups

# Obter grupo de logs específico
aws --endpoint-url=http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/file-processor-file-processor
```

### Verificar Tópicos SNS

```bash
# Listar tópicos SNS
aws --endpoint-url=http://localhost:4566 sns list-topics

# Obter atributos do tópico
aws --endpoint-url=http://localhost:4566 sns get-topic-attributes --topic-arn $(terraform output -raw file_received_topic_arn)
```

## Personalização

### Modificando a Função Lambda

1. Edite o arquivo `index.py` na função Lambda
2. Atualize a função `process_file_content` para implementar sua lógica de processamento específica
3. Recrie o arquivo zip e reimplante:

```bash
zip -r lambda_function.zip index.py
terraform apply -auto-approve
```

### Adicionando Variáveis de Ambiente

Modifique o recurso `aws_lambda_function` em `main.tf`:

```hcl
environment {
  variables = {
    OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
    SNS_TOPIC_ARN = aws_sns_topic.file_processed.arn
    # Adicione suas variáveis personalizadas aqui
    CUSTOM_VAR = "value"
  }
}
```

### Alterando Nomes de Recursos

Atualize a variável `project_name` em `main.tf` ou passe-a durante a implantação:

```bash
terraform apply -var="project_name=my-custom-pipeline"
```

## Solução de Problemas

### Problemas Comuns:

1. **LocalStack não está em execução**: Certifique-se de que o LocalStack está iniciado com `localstack start`
2. **Função Lambda não acionada**: Verifique as políticas da fila SQS e o mapeamento da fonte de eventos da Lambda
3. **Notificações S3 não funcionando**: Verifique se as políticas do tópico SNS permitem que o S3 publique
4. **Erros de permissão**: Verifique as funções e políticas IAM

### Comandos de Depuração:

```bash
# Verificar status dos serviços do LocalStack
curl http://localhost:4566/health

# Verificar se os recursos existem
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 sns list-topics
aws --endpoint-url=http://localhost:4566 sqs list-queues
aws --endpoint-url=http://localhost:4566 lambda list-functions
```

## Lógica de Processamento de Arquivos

A função Lambda inclui lógica de processamento de exemplo que:
- Converte arquivos de texto para maiúsculas
- Adiciona cabeçalhos de metadados
- Preserva arquivos binários com metadados de processamento
- Trata erros de forma elegante

Você pode personalizar a função `process_file_content` para suas necessidades específicas.

## Saídas de Recursos

Após a implantação, o Terraform fornece estas saídas:
- `input_bucket_name`: Bucket S3 para arquivos de entrada
- `output_bucket_name`: Bucket S3 para arquivos processados
- `file_received_topic_arn`: ARN do tópico SNS para arquivos recebidos
- `file_processed_topic_arn`: ARN do tópico SNS para arquivos processados
- `processing_queue_url`: URL da fila SQS para processamento
- `processed_queue_url`: URL da fila SQS para itens processados

## Exemplos de Uso

### Enviar um Arquivo para Processamento

```bash
aws --endpoint-url=http://localhost:4566 s3 cp meu_arquivo.txt s3://$INPUT_BUCKET/
```

### Verificar o Status da Fila de Processamento

```bash
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url $PROCESSING_QUEUE
```

### Obter Logs da Função Lambda

```bash
aws --endpoint-url=http://localhost:4566 logs get-log-events --log-group-name /aws/lambda/file-processor-file-processor --limit 10
```

### Listar Tópicos SNS

```bash
aws --endpoint-url=http://localhost:4566 sns list-topics
```

## Notas Finais

- Este projeto é destinado para desenvolvimento e testes locais usando LocalStack.
- Para implantação em ambientes de produção, considere as melhores práticas de segurança, escalabilidade e gerenciamento de custos.