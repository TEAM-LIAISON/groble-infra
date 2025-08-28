# Loki Service 출력
output "loki_service_name" {
  description = "Name of the Loki ECS service"
  value       = module.loki.loki_service_name
}

output "loki_endpoint" {
  description = "Loki HTTP endpoint for other services"
  value       = module.loki.loki_endpoint
}

output "loki_s3_bucket" {
  description = "S3 bucket used for Loki storage"
  value       = module.loki.loki_s3_bucket
}

# OpenTelemetry Collector Service 출력
output "otelcol_service_name" {
  description = "Name of the OpenTelemetry Collector ECS service"
  value       = module.otelcol.otelcol_service_name
}

output "otelcol_endpoint_http" {
  description = "OpenTelemetry Collector HTTP endpoint for OTLP"
  value       = module.otelcol.otelcol_endpoint_http
}

output "otelcol_endpoint_grpc" {
  description = "OpenTelemetry Collector gRPC endpoint for OTLP"
  value       = module.otelcol.otelcol_endpoint_grpc
}

output "otelcol_health_endpoint" {
  description = "OpenTelemetry Collector health check endpoint"
  value       = module.otelcol.otelcol_health_endpoint
}

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

# Prometheus Service 출력
output "prometheus_service_name" {
  description = "Name of the Prometheus ECS service"
  value       = module.prometheus.ecs_service_name
}

output "prometheus_endpoint" {
  description = "Prometheus internal endpoint"
  value       = module.prometheus.prometheus_endpoint
}

output "prometheus_s3_bucket" {
  description = "S3 bucket used for Prometheus storage"
  value       = module.prometheus.s3_bucket_name
}

output "prometheus_url" {
  description = "Prometheus access URL"
  value       = "https://${var.prometheus_domain}"
}

# 모니터링 스택 요약 (업데이트됨)
output "monitoring_stack_summary" {
  description = "Complete monitoring stack information"
  value = {
    loki = {
      service_name = module.loki.loki_service_name
      endpoint     = module.loki.loki_endpoint
      s3_bucket    = module.loki.loki_s3_bucket
    }
    otelcol = {
      service_name     = module.otelcol.otelcol_service_name
      http_endpoint    = module.otelcol.otelcol_endpoint_http
      grpc_endpoint    = module.otelcol.otelcol_endpoint_grpc
      health_endpoint  = module.otelcol.otelcol_health_endpoint
    }
    prometheus = {
      service_name = module.prometheus.ecs_service_name
      endpoint     = module.prometheus.prometheus_endpoint
      s3_bucket    = module.prometheus.s3_bucket_name
      url          = "https://${var.prometheus_domain}"
    }
    grafana = {
      service_name = module.grafana.ecs_service_name
      url          = "https://${var.grafana_domain}"
    }
  }
}
