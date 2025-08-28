variable "environment" {
  description = "Environment name"
  type        = string
  default     = "monitoring"
}

variable "ecs_cluster_id" {
  description = "ECS Cluster ID"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS Execution Role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN"
  type        = string
}

# Service discovery removed - using host networking

variable "otelcol_image" {
  description = "OpenTelemetry Collector Docker image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib"
}

variable "otelcol_version" {
  description = "OpenTelemetry Collector version"
  type        = string
  default     = "0.132.0"
}

# Loki endpoint hardcoded to localhost in config

variable "aws_region" {
  description = "AWS Region"
  type        = string
}


# Resource configuration
variable "cpu" {
  description = "CPU units for the task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory for the task (MB)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Hard memory limit for container (MB)"
  type        = number
  default     = 256
}

variable "container_memory_reservation" {
  description = "Soft memory limit for container (MB)"
  type        = number
  default     = 128
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# Health check configuration
variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 60
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}


# Future: Prometheus configuration
variable "enable_prometheus_export" {
  description = "Enable Prometheus metrics export (future feature)"
  type        = bool
  default     = false
}

variable "prometheus_endpoint" {
  description = "Prometheus endpoint for metrics export (future feature)"
  type        = string
  default     = ""
}

