output "service_name" {
  description = "RDS Exporter service name"
  value       = aws_ecs_service.rds_exporter.name
}

output "task_definition_arn" {
  description = "RDS Exporter task definition ARN"
  value       = aws_ecs_task_definition.rds_exporter.arn
}
