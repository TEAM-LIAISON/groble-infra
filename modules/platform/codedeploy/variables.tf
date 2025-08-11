variable "project_name" {
  description = "Project name"
  type        = string
}

# Deployment Group 생성 여부
variable "create_prod_deployment_group" {
  description = "Create production deployment group"
  type        = bool
  default     = true
}

variable "create_dev_deployment_group" {
  description = "Create development deployment group"
  type        = bool
  default     = true
}

variable "create_artifacts_bucket" {
  description = "Create S3 bucket for CodeDeploy artifacts"
  type        = bool
  default     = true
}

# IAM Role
variable "codedeploy_service_role_arn" {
  description = "CodeDeploy service role ARN"
  type        = string
}

# ECS 관련 설정
variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "prod_service_name" {
  description = "Production ECS service name"
  type        = string
  default     = ""
}

variable "dev_service_name" {
  description = "Development ECS service name"
  type        = string
  default     = ""
}

# Deployment Configuration
variable "prod_deployment_config" {
  description = "Production deployment configuration"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "dev_deployment_config" {
  description = "Development deployment configuration"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

# Blue/Green 배포 설정
variable "deployment_ready_timeout_action" {
  description = "Action on deployment ready timeout"
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_timeout_action)
    error_message = "Deployment ready timeout action must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}

variable "deployment_ready_wait_time" {
  description = "Wait time in minutes for deployment ready"
  type        = number
  default     = 0
}

variable "termination_wait_time" {
  description = "Wait time in minutes before terminating blue instances"
  type        = number
  default     = 2
}

# Load Balancer 설정
variable "prod_blue_target_group_name" {
  description = "Production blue target group name"
  type        = string
  default     = ""
}

variable "prod_green_target_group_name" {
  description = "Production green target group name"
  type        = string
  default     = ""
}

variable "dev_blue_target_group_name" {
  description = "Development blue target group name"
  type        = string
  default     = ""
}

variable "dev_green_target_group_name" {
  description = "Development green target group name"
  type        = string
  default     = ""
}

variable "prod_listener_arns" {
  description = "Production traffic listener ARNs"
  type        = list(string)
  default     = []
}

variable "test_listener_arns" {
  description = "Test traffic listener ARNs"
  type        = list(string)
  default     = []
}

# 자동 롤백 설정
variable "enable_auto_rollback" {
  description = "Enable automatic rollback"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
}

# 알람 설정
variable "enable_alarm_configuration" {
  description = "Enable alarm configuration"
  type        = bool
  default     = false
}

variable "alarm_names" {
  description = "List of CloudWatch alarm names"
  type        = list(string)
  default     = []
}

# Note: ECS service dependencies are managed at the main.tf level
# where CodeDeploy module is called after ECS services are created
