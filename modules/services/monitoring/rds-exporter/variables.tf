variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "rds_exporter_image" {
  description = "RDS Exporter Docker image (MySQL exporter compatible)"
  type        = string
  default     = "prom/mysqld-exporter"
}

variable "rds_exporter_version" {
  description = "RDS Exporter version"
  type        = string
  default     = "v0.15.1"
}

variable "rds_endpoint" {
  description = "RDS endpoint address (without port)"
  type        = string
}

variable "database_username" {
  description = "RDS database username"
  type        = string
  sensitive   = true
}

variable "database_password" {
  description = "RDS database password"
  type        = string
  sensitive   = true
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 128
}

variable "memory" {
  description = "Task memory in MB"
  type        = number
  default     = 128
}

variable "container_memory" {
  description = "Container memory limit in MB"
  type        = number
  default     = 128
}

variable "container_memory_reservation" {
  description = "Container memory reservation in MB"
  type        = number
  default     = 64
}
