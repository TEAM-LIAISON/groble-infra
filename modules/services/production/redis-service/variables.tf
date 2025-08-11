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

# Redis 설정
variable "redis_memory" {
  description = "Memory allocation for Redis container"
  type        = number
  default     = 128
}

variable "redis_cpu" {
  description = "CPU allocation for Redis container"
  type        = number
  default     = 128
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}
