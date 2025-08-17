output "ecs_service_arn" {
  description = "ARN of the Grafana ECS service"
  value       = aws_ecs_service.grafana.id
}

output "ecs_service_name" {
  description = "Name of the Grafana ECS service"
  value       = aws_ecs_service.grafana.name
}

output "task_definition_arn" {
  description = "ARN of the Grafana task definition"
  value       = aws_ecs_task_definition.grafana.arn
}

output "task_definition_family" {
  description = "Family of the Grafana task definition"
  value       = aws_ecs_task_definition.grafana.family
}

output "task_definition_revision" {
  description = "Revision of the Grafana task definition"
  value       = aws_ecs_task_definition.grafana.revision
}
