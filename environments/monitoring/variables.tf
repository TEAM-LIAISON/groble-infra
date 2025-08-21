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

variable "cpu" {
  description = "CPU units for the task (250 = 0.25 vCPU)"
  type        = number
  default     = 250
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
