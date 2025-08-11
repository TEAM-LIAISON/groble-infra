output "task_definition_arn" {
  description = "API task definition ARN"
  value       = aws_ecs_task_definition.api_task.arn
}

output "service_name" {
  description = "API service name"
  value       = aws_ecs_service.api_service.name
}

output "service_id" {
  description = "API service ID"
  value       = aws_ecs_service.api_service.id
}

output "task_definition_family" {
  description = "API task definition family"
  value       = aws_ecs_task_definition.api_task.family
}

output "service_arn" {
  description = "API service ARN"
  value       = aws_ecs_service.api_service.id
}
