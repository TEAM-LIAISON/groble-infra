output "service_name" {
  description = "Node Exporter service name"
  value       = aws_ecs_service.node_exporter.name
}

output "task_definition_arn" {
  description = "Node Exporter task definition ARN"
  value       = aws_ecs_task_definition.node_exporter.arn
}
