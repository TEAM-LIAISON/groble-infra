output "otelcol_service_name" {
  description = "OpenTelemetry Collector ECS service name"
  value       = aws_ecs_service.otelcol.name
}

output "otelcol_service_arn" {
  description = "OpenTelemetry Collector ECS service ARN"
  value       = aws_ecs_service.otelcol.id
}

# Service discovery removed - using host networking

output "otelcol_task_definition_arn" {
  description = "OpenTelemetry Collector task definition ARN"
  value       = aws_ecs_task_definition.otelcol.arn
}

output "otelcol_task_definition_family" {
  description = "OpenTelemetry Collector task definition family"
  value       = aws_ecs_task_definition.otelcol.family
}

output "otelcol_task_definition_revision" {
  description = "OpenTelemetry Collector task definition revision"
  value       = aws_ecs_task_definition.otelcol.revision
}



# Service endpoints - localhost with host networking
output "otelcol_endpoint_http" {
  description = "OpenTelemetry Collector HTTP endpoint for OTLP"
  value       = "http://localhost:4318"
}

output "otelcol_endpoint_grpc" {
  description = "OpenTelemetry Collector gRPC endpoint for OTLP"
  value       = "http://localhost:4317"
}

output "otelcol_health_endpoint" {
  description = "OpenTelemetry Collector health check endpoint"
  value       = "http://localhost:13133"
}

output "otelcol_metrics_endpoint" {
  description = "OpenTelemetry Collector internal metrics endpoint"
  value       = "http://localhost:8888/metrics"
}

# output "otelcol_zpages_endpoint" {
#   description = "OpenTelemetry Collector Z-pages debugging endpoint"
#   value       = "http://localhost:55679/debug"
# }

# Network configuration for external reference
output "otelcol_ports" {
  description = "OpenTelemetry Collector port configuration"
  value = {
    otlp_http   = 4318
    otlp_grpc   = 4317
    health      = 13133
    metrics     = 8888
    # zpages      = 55679
  }
}

# Templated configuration content
output "otelcol_config_content" {
  description = "Rendered OpenTelemetry Collector configuration content"
  value       = local.otelcol_config
}

# Configuration summary
output "deployment_summary" {
  description = "Deployment configuration summary"
  value = {
    service_name           = aws_ecs_service.otelcol.name
    service_discovery_name = "localhost"
    placement_constraint   = "attribute:environment == monitoring"
    cpu_units             = var.cpu
    memory_mb             = var.memory
    desired_count         = var.desired_count
    loki_endpoint         = "http://localhost:3100"
    collector_version     = var.otelcol_version
    cloudwatch_logs       = false
    security_group_created = false
  }
}

# Service discovery service removed - using host networking
