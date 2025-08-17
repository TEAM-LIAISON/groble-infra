variable "environment" {
  description = "Environment name"
  type        = string
  default     = "monitoring"
}

variable "ecs_cluster_id" {
  description = "ECS Cluster ID"
  type        = string
}

variable "target_group_arn" {
  description = "ALB Target Group ARN for Grafana"
  type        = string
}

variable "alb_listener" {
  description = "ALB Listener"
}

variable "execution_role_arn" {
  description = "ECS Execution Role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN"
  type        = string
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

variable "admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
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

# 낮은 리소스 설정
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

variable "aws_region" {
  description = "AWS Region"
  type        = string
}
