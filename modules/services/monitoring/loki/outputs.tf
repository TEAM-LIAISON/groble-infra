output "loki_service_name" {
  description = "Loki ECS service name"
  value       = aws_ecs_service.loki.name
}

output "loki_service_discovery_arn" {
  description = "Loki service discovery ARN"
  value       = aws_service_discovery_service.loki.arn
}

output "loki_endpoint" {
  description = "Loki HTTP endpoint for other services"
  value       = "http://loki.groble.local:3100"
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
