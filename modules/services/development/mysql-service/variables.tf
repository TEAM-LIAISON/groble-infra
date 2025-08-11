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

# MySQL 설정
variable "mysql_memory" {
  description = "Memory allocation for MySQL container"
  type        = number
  default     = 400
}

variable "mysql_cpu" {
  description = "CPU allocation for MySQL container"
  type        = number
  default     = 256
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "mysql_database" {
  description = "MySQL database name"
  type        = string
}
