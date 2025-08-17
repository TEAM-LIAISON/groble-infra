# Grafana Service 출력
output "grafana_service_arn" {
  description = "ARN of the Grafana ECS service"
  value       = module.grafana.ecs_service_arn
}

output "grafana_service_name" {
  description = "Name of the Grafana ECS service"
  value       = module.grafana.ecs_service_name
}

output "grafana_task_definition_arn" {
  description = "ARN of the Grafana task definition"
  value       = module.grafana.task_definition_arn
}

# ALB Target Group 출력 (from shared environment)
output "grafana_target_group_arn" {
  description = "ARN of the Grafana target group"
  value       = data.terraform_remote_state.shared.outputs.monitoring_target_group_arn
}

# 접속 정보
output "grafana_url" {
  description = "Grafana access URL"
  value       = "https://${var.grafana_domain}"
}
