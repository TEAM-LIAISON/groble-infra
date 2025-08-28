output "loki_service_name" {
  description = "Loki ECS service name"
  value       = aws_ecs_service.loki.name
}

# Service discovery removed - using host networking

output "loki_endpoint" {
  description = "Loki HTTP endpoint for other services"
  value       = "http://localhost:3100"
}

output "loki_s3_bucket" {
  description = "S3 bucket used for Loki storage"
  value       = aws_s3_bucket.loki_storage.bucket
}

output "loki_s3_bucket_arn" {
  description = "S3 bucket ARN used for Loki storage"
  value       = aws_s3_bucket.loki_storage.arn
}

output "loki_task_definition_arn" {
  description = "Loki task definition ARN"
  value       = aws_ecs_task_definition.loki.arn
}

# Service discovery service removed - using host networking
