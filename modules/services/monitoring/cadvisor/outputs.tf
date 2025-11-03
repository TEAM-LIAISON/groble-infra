output "service_name" {
  description = "cAdvisor service name"
  value       = aws_ecs_service.cadvisor.name
}

output "task_definition_arn" {
  description = "cAdvisor task definition ARN"
  value       = aws_ecs_task_definition.cadvisor.arn
}
