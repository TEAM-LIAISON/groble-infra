# Environment and Infrastructure
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "monitoring"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

# ECS Configuration
variable "ecs_cluster_id" {
  description = "ECS cluster ID where Prometheus will be deployed"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

# Service discovery removed - using host networking with localhost

# Prometheus Configuration
variable "prometheus_image" {
  description = "Prometheus Docker image"
  type        = string
  default     = "prom/prometheus"
}

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.45.0"
}

variable "prometheus_domain" {
  description = "Prometheus domain for external URL"
  type        = string
  default     = "prometheus.example.com"
}

# Resource Configuration
variable "cpu" {
  description = "CPU units for Prometheus task (1024 = 1 vCPU)"
  type        = number
  default     = 512  # 0.5 vCPU
}

variable "memory" {
  description = "Memory in MB for Prometheus task"
  type        = number
  default     = 512  # 0.5GB (reduced from 1GB)
}

variable "container_memory" {
  description = "Hard memory limit for Prometheus container"
  type        = number
  default     = 512  # reduced from 1024
}

variable "container_memory_reservation" {
  description = "Soft memory limit for Prometheus container"
  type        = number
  default     = 256  # reduced from 384
}

variable "desired_count" {
  description = "Desired number of Prometheus instances"
  type        = number
  default     = 1
}

# Storage Configuration
variable "metrics_retention_days" {
  description = "S3 metrics retention period in days"
  type        = number
  default     = 90  # 3 months
}

variable "local_retention_time" {
  description = "Local TSDB retention time"
  type        = string
  default     = "15d"
}

variable "local_retention_size" {
  description = "Local TSDB retention size"
  type        = string
  default     = "10GB"
}

# Prometheus Settings
variable "scrape_interval" {
  description = "Global scrape interval"
  type        = string
  default     = "15s"
}

variable "evaluation_interval" {
  description = "Rule evaluation interval"
  type        = string
  default     = "30s"
}

variable "log_level" {
  description = "Prometheus log level"
  type        = string
  default     = "info"
}

# Integration Endpoints
variable "otelcol_endpoint" {
  description = "OpenTelemetry Collector endpoint"
  type        = string
  default     = "localhost:8888"
}

# Load Balancer (Optional)
variable "target_group_arn" {
  description = "ALB target group ARN for Prometheus (optional)"
  type        = string
  default     = ""
}

variable "alb_listener" {
  description = "ALB listener dependency (optional)"
  type        = any
  default     = null
}

# Health Check
variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}