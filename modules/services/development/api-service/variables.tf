variable "project_name" {
  description = "Project name"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

# Container 설정
variable "spring_app_image" {
  description = "Spring application Docker image"
  type        = string
}

variable "memory_reservation" {
  description = "Memory reservation for container"
  type        = number
  default     = 400
}

variable "memory_limit" {
  description = "Memory limit for container"
  type        = number
  default     = 700
}

variable "cpu" {
  description = "CPU allocation for container"
  type        = number
  default     = 256
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# Application 설정
variable "spring_profiles" {
  description = "Spring active profiles"
  type        = string
}

variable "server_env" {
  description = "Server environment"
  type        = string
}

# Database 설정
variable "db_host" {
  description = "Database host"
  type        = string
}

variable "mysql_database" {
  description = "MySQL database name"
  type        = string
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

# Redis 설정
variable "redis_host" {
  description = "Redis host"
  type        = string
}

# OpenTelemetry 설정
variable "otel_exporter_endpoint" {
  description = "OpenTelemetry exporter endpoint"
  type        = string
}


# Network 설정
variable "subnet_ids" {
  description = "List of subnet IDs for ECS service"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS service"
  type        = list(string)
}

# Load Balancer 설정
variable "target_group_arn" {
  description = "ALB target group ARN for the service"
  type        = string
}

