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

variable "node_exporter_image" {
  description = "Node Exporter Docker image"
  type        = string
  default     = "prom/node-exporter"
}

variable "node_exporter_version" {
  description = "Node Exporter version"
  type        = string
  default     = "v1.8.2"
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
