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

variable "cadvisor_image" {
  description = "cAdvisor Docker image"
  type        = string
  default     = "gcr.io/cadvisor/cadvisor"
}

variable "cadvisor_version" {
  description = "cAdvisor version"
  type        = string
  default     = "v0.49.1"
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 128
}

variable "memory" {
  description = "Task memory in MB"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Container memory limit in MB"
  type        = number
  default     = 256
}

variable "container_memory_reservation" {
  description = "Container memory reservation in MB"
  type        = number
  default     = 128
}
