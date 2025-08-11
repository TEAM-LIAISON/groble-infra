# AWS 기본 설정 변수들
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name for shared resources"
  type        = string
  default     = "shared"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "groble"
}

# VPC 관련 변수들
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# EC2 인스턴스 관련 변수들
variable "key_pair_name" {
  description = "Name of the AWS key pair for EC2 instances"
  type        = string
  default     = ""
}

variable "prod_instance_count" {
  description = "Number of production EC2 instances"
  type        = number
  default     = 1
}

variable "prod_instance_type" {
  description = "Production EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  description = "Monitoring EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "dev_instance_type" {
  description = "Development EC2 instance type"
  type        = string
  default     = "t3.small"
}

# 로드 밸런서 관련 변수들
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
}

# SSH 접근 관련 변수들
variable "trusted_ips" {
  description = "List of trusted IP addresses for direct SSH access to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# SSL 인증서 관련 변수들
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  default     = ""
}

variable "additional_ssl_certificate_arn" {
  description = "Additional SSL certificate ARN for ALB"
  type        = string
  default     = ""
}

# CodeDeploy 관련 변수들
variable "prod_deployment_config" {
  description = "CodeDeploy deployment configuration for production"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "dev_deployment_config" {
  description = "CodeDeploy deployment configuration for development"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "deployment_ready_timeout_action" {
  description = "Action to take when deployment is ready timeout"
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
}

variable "deployment_ready_wait_time" {
  description = "Time to wait before deployment ready timeout (minutes)"
  type        = number
  default     = 0
}

variable "termination_wait_time" {
  description = "Time to wait before terminating old tasks (minutes)"
  type        = number
  default     = 2
}

variable "enable_auto_rollback" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
}

variable "enable_alarm_configuration" {
  description = "Enable CloudWatch alarm configuration for deployments"
  type        = bool
  default     = false
}

variable "alarm_names" {
  description = "List of CloudWatch alarm names to monitor during deployment"
  type        = list(string)
  default     = []
}
