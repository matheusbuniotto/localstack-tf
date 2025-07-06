output "secret_arn" {
  description = "O ARN do segredo armazenado no Secrets Manager"
  value       = aws_secretsmanager_secret.api_key.arn
}