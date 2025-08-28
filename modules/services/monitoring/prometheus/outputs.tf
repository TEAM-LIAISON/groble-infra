output "ecs_service_arn" {
  description = "ARN of the Prometheus ECS service"
  value       = aws_ecs_service.prometheus.id
}

output "ecs_service_name" {
  description = "Name of the Prometheus ECS service"
  value       = aws_ecs_service.prometheus.name
}

output "task_definition_arn" {
  description = "ARN of the Prometheus task definition"
  value       = aws_ecs_task_definition.prometheus.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name for Prometheus storage"
  value       = aws_s3_bucket.prometheus_storage.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for Prometheus storage"
  value       = aws_s3_bucket.prometheus_storage.arn
}

# Service discovery removed - using host networking

output "prometheus_endpoint" {
  description = "Prometheus internal endpoint"
  value       = "http://localhost:9090"
}

output "prometheus_config_content" {
  description = "Prometheus configuration content (via environment variable)"
  value       = "Configuration loaded dynamically via PROMETHEUS_CONFIG_YAML environment variable"
}
