# AWS 기본 설정 변수들
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-northeast-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'ap-northeast-2'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
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
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability."
  }
}

# 서브넷 CIDR 블록들
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

variable "monitoring_instance_type" {
  description = "Monitoring EC2 instance type"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3.xlarge", "t3.2xlarge", "t2.micro"
    ], var.monitoring_instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
}

variable "dev_instance_type" {
  description = "Development EC2 instance type"
  type        = string
  default     = "t3.small"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3.xlarge", "t3.2xlarge", "t2.micro"
    ], var.dev_instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
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
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

# SSH 접근 관련 변수들
variable "trusted_ips" {
  description = "List of trusted IP addresses for direct SSH access to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition     = length(var.trusted_ips) > 0
    error_message = "At least one trusted IP must be specified."
  }
}

# SSL 인증서 관련 변수들
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", var.ssl_certificate_arn)) || var.ssl_certificate_arn == ""
    error_message = "SSL certificate ARN must be a valid ACM certificate ARN or empty string."
  }
}

variable "additional_ssl_certificate_arn" {
  description = "Additional SSL certificate ARN for ALB"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", var.additional_ssl_certificate_arn)) || var.additional_ssl_certificate_arn == ""
    error_message = "Additional SSL certificate ARN must be a valid ACM certificate ARN or empty string."
  }
}

# ECR 관련 변수들
variable "dev_max_image_count" {
  description = "Maximum number of images to keep in development ECR repository"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dev_max_image_count > 0
    error_message = "Maximum image count must be greater than 0."
  }
}

# MySQL 관련 변수들
variable "mysql_memory" {
  description = "Memory allocation for MySQL container (MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.mysql_memory >= 128
    error_message = "MySQL memory must be at least 128 MB."
  }
}

variable "mysql_cpu" {
  description = "CPU allocation for MySQL container"
  type        = number
  default     = 128
  
  validation {
    condition     = var.mysql_cpu >= 128
    error_message = "MySQL CPU must be at least 128."
  }
}

variable "mysql_root_password" {
  description = "Root password for MySQL database"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_root_password) >= 8
    error_message = "MySQL root password must be at least 8 characters long."
  }
}

variable "mysql_database" {
  description = "MySQL database name"
  type        = string
  default     = "groble_develop_database"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_database))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# Redis 관련 변수들
variable "redis_memory" {
  description = "Memory allocation for Redis container (MB)"
  type        = number
  default     = 128
  
  validation {
    condition     = var.redis_memory >= 64
    error_message = "Redis memory must be at least 64 MB."
  }
}

variable "redis_cpu" {
  description = "CPU allocation for Redis container"
  type        = number
  default     = 128
  
  validation {
    condition     = var.redis_cpu >= 64
    error_message = "Redis CPU must be at least 64."
  }
}

variable "redis_password" {
  description = "Password for Redis"
  type        = string
  sensitive   = true
  default     = ""
}

# API 서비스 관련 변수들
variable "spring_app_image" {
  description = "Docker image for Spring Boot application"
  type        = string
  default     = "openjdk:17-jdk-slim"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.spring_app_image))
    error_message = "Spring app image must be a valid Docker image format (image:tag)."
  }
}

variable "api_memory_reservation" {
  description = "Memory reservation for API container (MB)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.api_memory_reservation >= 128
    error_message = "API memory reservation must be at least 128 MB."
  }
}

variable "api_memory_limit" {
  description = "Memory limit for API container (MB)"
  type        = number
  default     = 700
  
  validation {
    condition     = var.api_memory_limit >= 400
    error_message = "API memory limit must be at least 400 MB."
  }
}

variable "api_cpu" {
  description = "CPU allocation for API container"
  type        = number
  default     = 256
  
  validation {
    condition     = var.api_cpu >= 128
    error_message = "API CPU must be at least 128."
  }
}

variable "api_desired_count" {
  description = "Desired number of API service tasks"
  type        = number
  default     = 1
  
  validation {
    condition     = var.api_desired_count >= 1
    error_message = "API desired count must be at least 1."
  }
}

variable "spring_profiles" {
  description = "Spring profiles for the environment"
  type        = string
  default     = "dev,common,secret-dev,proxy"
  
  validation {
    condition     = length(var.spring_profiles) > 0
    error_message = "Spring profiles must not be empty."
  }
}

variable "server_env" {
  description = "Server environment"
  type        = string
  default     = "development"
}

# CodeDeploy 관련 변수들
variable "deployment_config" {
  description = "CodeDeploy deployment configuration"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  
  validation {
    condition = contains([
      "CodeDeployDefault.ECSAllAtOnce",
      "CodeDeployDefault.ECSLinear10PercentEvery1Minutes",
      "CodeDeployDefault.ECSLinear10PercentEvery3Minutes",
      "CodeDeployDefault.ECSCanary10Percent5Minutes",
      "CodeDeployDefault.ECSCanary10Percent15Minutes"
    ], var.deployment_config)
    error_message = "Deployment config must be a valid ECS deployment configuration."
  }
}

variable "deployment_ready_timeout_action" {
  description = "Action to take when deployment is ready timeout"
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  
  validation {
    condition = contains([
      "CONTINUE_DEPLOYMENT",
      "STOP_DEPLOYMENT"
    ], var.deployment_ready_timeout_action)
    error_message = "Deployment ready timeout action must be either CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}

variable "deployment_ready_wait_time" {
  description = "Time to wait before deployment ready timeout (minutes)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.deployment_ready_wait_time >= 0
    error_message = "Deployment ready wait time must be non-negative."
  }
}

variable "termination_wait_time" {
  description = "Time to wait before terminating old tasks (minutes)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.termination_wait_time >= 0
    error_message = "Termination wait time must be non-negative."
  }
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
  
  validation {
    condition = alltrue([
      for event in var.auto_rollback_events : contains([
        "DEPLOYMENT_FAILURE",
        "DEPLOYMENT_STOP_ON_ALARM",
        "DEPLOYMENT_STOP_ON_REQUEST"
      ], event)
    ])
    error_message = "Auto rollback events must be valid deployment events."
  }
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
