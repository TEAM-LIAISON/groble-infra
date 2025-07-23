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
  default     = "prod"
  
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
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3.xlarge", "t3.2xlarge", "t2.micro"
    ], var.instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for EC2 instances"
  type        = string
  default     = ""
}

# 로드 밸런서 관련 변수들
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

# SSH 접근 관련 변수들
variable "trusted_ips" {
  description = "List of trusted IP addresses for direct SSH access to EC2 instances (Public Subnet deployment)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # 개발 중에는 모든 IP 허용, 나중에 특정 IP로 변경 권장
  
  validation {
    condition     = length(var.trusted_ips) > 0
    error_message = "At least one trusted IP must be specified."
  }
}

# ECS 및 헬스체크 관련 변수들
variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "enable_blue_green" {
  description = "Enable Blue/Green deployment target groups"
  type        = bool
  default     = true
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

# 데이터베이스 관련 변수들
variable "mysql_prod_root_password" {
  description = "Root password for production MySQL database"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_prod_root_password) >= 8
    error_message = "MySQL root password must be at least 8 characters long."
  }
}

variable "mysql_prod_database" {
  description = "Production MySQL database name"
  type        = string
  default     = "groble_prod_database"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_prod_database))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "mysql_prod_user" {
  description = "Production MySQL database user"
  type        = string
  default     = "groble_root"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_prod_user))
    error_message = "Database user must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "mysql_prod_password" {
  description = "Password for production MySQL database user"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_prod_password) >= 8
    error_message = "MySQL user password must be at least 8 characters long."
  }
}

variable "mysql_dev_root_password" {
  description = "Root password for development MySQL database"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_dev_root_password) >= 8
    error_message = "MySQL root password must be at least 8 characters long."
  }
}

variable "mysql_dev_database" {
  description = "Development MySQL database name"
  type        = string
  default     = "groble_develop_database"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_dev_database))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "mysql_dev_user" {
  description = "Development MySQL database user"
  type        = string
  default     = "groble_root"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_dev_user))
    error_message = "Database user must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "mysql_dev_password" {
  description = "Password for development MySQL database user"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_dev_password) >= 8
    error_message = "MySQL user password must be at least 8 characters long."
  }
}

# Spring Boot 애플리케이션 이미지 관련 변수들
variable "spring_app_image_prod" {
  description = "Docker image for production Spring Boot application"
  type        = string
  default     = "openjdk:17-jdk-slim"  # 실제 이미지 URL로 변경 필요
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.spring_app_image_prod))
    error_message = "Spring app image must be a valid Docker image format (image:tag)."
  }
}

variable "spring_app_image_dev" {
  description = "Docker image for development Spring Boot application"
  type        = string
  default     = "openjdk:17-jdk-slim"  # 실제 이미지 URL로 변경 필요
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.spring_app_image_dev))
    error_message = "Spring app image must be a valid Docker image format (image:tag)."
  }
}

# Spring Boot Profiles 관련 변수들
variable "spring_profiles_prod" {
  description = "Spring profiles for production environment"
  type        = string
  default     = "prod,common,secret-prod"
  
  validation {
    condition     = length(var.spring_profiles_prod) > 0
    error_message = "Spring profiles must not be empty."
  }
}

variable "spring_profiles_dev" {
  description = "Spring profiles for development environment"
  type        = string
  default     = "dev,common,secret-dev"
  
  validation {
    condition     = length(var.spring_profiles_dev) > 0
    error_message = "Spring profiles must not be empty."
  }
}

variable "server_env_prod" {
  description = "Server environment for production"
  type        = string
  default     = "production"
}

variable "server_env_dev" {
  description = "Server environment for development"
  type        = string
  default     = "development"
}
