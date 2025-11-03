variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "grafana_image" {
  description = "Grafana Docker image"
  type        = string
  default     = "grafana/grafana"
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "latest"
}

variable "grafana_domain" {
  description = "Grafana domain name"
  type        = string
}

variable "grafana_plugins" {
  description = "Grafana plugins to install"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_cpu" {
  description = "CPU units for the Grafana task (250 = 0.25 vCPU)"
  type        = number
  default     = 250
}

variable "grafana_memory" {
  description = "Memory for the Grafana task (MB)"
  type        = number
  default     = 256
}

variable "grafana_container_memory" {
  description = "Hard memory limit for Grafana container (MB)"
  type        = number
  default     = 256
}

variable "grafana_container_memory_reservation" {
  description = "Soft memory limit for Grafana container (MB)"
  type        = number
  default     = 128
}

variable "grafana_desired_count" {
  description = "Desired number of Grafana tasks"
  type        = number
  default     = 1
}

# Loki 관련 변수
variable "loki_image" {
  description = "Loki Docker image"
  type        = string
  default     = "grafana/loki"
}

variable "loki_version" {
  description = "Loki version"
  type        = string
  default     = "3.0.0"
}

variable "loki_log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}

variable "loki_cpu" {
  description = "CPU units for Loki task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "loki_memory" {
  description = "Memory for Loki task (MB)"
  type        = number
  default     = 512
}

variable "loki_container_memory" {
  description = "Hard memory limit for Loki container (MB)"
  type        = number
  default     = 512
}

variable "loki_container_memory_reservation" {
  description = "Soft memory limit for Loki container (MB)"
  type        = number
  default     = 256
}

# OpenTelemetry Collector 관련 변수
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

variable "otelcol_cpu" {
  description = "CPU units for OpenTelemetry Collector task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "otelcol_memory" {
  description = "Memory for OpenTelemetry Collector task (MB)"
  type        = number
  default     = 256
}

variable "otelcol_container_memory" {
  description = "Hard memory limit for OpenTelemetry Collector container (MB)"
  type        = number
  default     = 256
}

variable "otelcol_container_memory_reservation" {
  description = "Soft memory limit for OpenTelemetry Collector container (MB)"
  type        = number
  default     = 128
}

# Prometheus 관련 변수
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
  description = "Prometheus domain name"
  type        = string
  default     = "prometheus.example.com"
}

variable "prometheus_target_group_arn" {
  description = "ALB target group ARN for Prometheus (optional)"
  type        = string
  default     = ""
}

variable "prometheus_cpu" {
  description = "CPU units for Prometheus task (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "prometheus_memory" {
  description = "Memory for Prometheus task (MB)"
  type        = number
  default     = 1024
}

variable "prometheus_container_memory" {
  description = "Hard memory limit for Prometheus container (MB)"
  type        = number
  default     = 1024
}

variable "prometheus_container_memory_reservation" {
  description = "Soft memory limit for Prometheus container (MB)"
  type        = number
  default     = 768
}

variable "prometheus_metrics_retention_days" {
  description = "S3 metrics retention period in days"
  type        = number
  default     = 90
}

variable "prometheus_local_retention_time" {
  description = "Local TSDB retention time"
  type        = string
  default     = "15d"
}

variable "prometheus_local_retention_size" {
  description = "Local TSDB retention size"
  type        = string
  default     = "10GB"
}

variable "prometheus_scrape_interval" {
  description = "Global scrape interval"
  type        = string
  default     = "15s"
}

variable "prometheus_evaluation_interval" {
  description = "Rule evaluation interval"
  type        = string
  default     = "30s"
}

variable "prometheus_log_level" {
  description = "Prometheus log level"
  type        = string
  default     = "info"
}

# Common service configuration
variable "desired_count" {
  description = "Desired number of tasks for services (except Grafana which has its own variable)"
  type        = number
  default     = 1
}

# RDS Exporter configuration
variable "rds_endpoint" {
  description = "RDS endpoint address for monitoring"
  type        = string
  default     = ""
}

variable "rds_database_username" {
  description = "RDS database username for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rds_database_password" {
  description = "RDS database password for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

