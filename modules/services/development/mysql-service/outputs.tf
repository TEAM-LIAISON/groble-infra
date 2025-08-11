output "task_definition_arn" {
  description = "MySQL task definition ARN"
  value       = aws_ecs_task_definition.mysql_task.arn
}

output "service_name" {
  description = "MySQL service name"
  value       = aws_ecs_service.mysql_service.name
}

output "service_id" {
  description = "MySQL service ID"
  value       = aws_ecs_service.mysql_service.id
}

output "task_definition_family" {
  description = "MySQL task definition family"
  value       = aws_ecs_task_definition.mysql_task.family
}
