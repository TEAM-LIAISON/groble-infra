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
