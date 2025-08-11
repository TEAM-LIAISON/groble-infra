output "task_definition_arn" {
  description = "Redis task definition ARN"
  value       = aws_ecs_task_definition.redis_task.arn
}

output "service_name" {
  description = "Redis service name"
  value       = aws_ecs_service.redis_service.name
}

output "service_id" {
  description = "Redis service ID"
  value       = aws_ecs_service.redis_service.id
}

output "task_definition_family" {
  description = "Redis task definition family"
  value       = aws_ecs_task_definition.redis_task.family
}
