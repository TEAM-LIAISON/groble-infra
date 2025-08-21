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

variable "service_discovery_namespace_id" {
  description = "Service Discovery Namespace ID"
  type        = string
}

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

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 14
}

# 리소스 설정 (최적화된 리소스 사용)
variable "cpu" {
  description = "CPU units for the task (250 = 0.25 vCPU)"
  type        = number
  default     = 250
}

variable "memory" {
  description = "Memory for the task (MB)"
  type        = number
  default     = 512
}

variable "container_memory" {
  description = "Hard memory limit for container (MB)"
  type        = number
  default     = 512
}

variable "container_memory_reservation" {
  description = "Soft memory limit for container (MB)"
  type        = number
  default     = 256
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "ssm_parameter_name" {
  description = "SSM Parameter name for Loki configuration"
  type        = string
  default     = ""
}
