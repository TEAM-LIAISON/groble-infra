#################################
# Shared Variables for Groble Infrastructure
#################################
# 
# 이 파일은 모든 환경에서 공통으로 사용되는 변수들을 정의합니다.
# 각 환경의 variables.tf에서 이 파일을 참조하여 일관성을 유지합니다.

#################################
# AWS 기본 설정 변수들
#################################

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-northeast-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'ap-northeast-2'."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "groble"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

#################################
# VPC 네트워크 관련 공통 변수들
#################################

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

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "Number of public subnet CIDRs must match number of availability zones."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
  
  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "Number of private subnet CIDRs must match number of availability zones."
  }
}

#################################
# 보안 관련 공통 변수들
#################################

variable "key_pair_name" {
  description = "Name of the AWS key pair for EC2 instances"
  type        = string
  default     = ""
  
  validation {
    condition     = var.key_pair_name == "" || can(regex("^[a-zA-Z0-9_-]+$", var.key_pair_name))
    error_message = "Key pair name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "trusted_ips" {
  description = "List of trusted IP addresses for direct SSH access to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition     = length(var.trusted_ips) > 0
    error_message = "At least one trusted IP must be specified."
  }
}

#################################
# SSL 인증서 관련 공통 변수들
#################################

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

#################################
# 애플리케이션 공통 변수들
#################################

variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "spring_app_image_base" {
  description = "Base Docker image for Spring Boot application"
  type        = string
  default     = "openjdk:17-jdk-slim"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.spring_app_image_base))
    error_message = "Spring app image must be a valid Docker image format (image:tag)."
  }
}

#################################
# 리소스 크기 관련 공통 기본값
#################################

# 인스턴스 타입 검증 함수
locals {
  valid_instance_types = [
    "t3.micro", "t3.small", "t3.medium", "t3.large",
    "t3.xlarge", "t3.2xlarge", "t2.micro"
  ]
}

# 컨테이너 리소스 최소값
locals {
  min_memory = 64
  min_cpu    = 64
}

#################################
# 태그 관련 공통 변수들
#################################

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "Groble Infrastructure"
    ManagedBy = "Terraform"
    CreatedBy = "jemin"
  }
}

#################################
# 환경별 오버라이드 가능한 기본값들
#################################

# 이 변수들은 각 환경에서 오버라이드할 수 있습니다.
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for ECS cluster"
  type        = bool
  default     = false
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting for ECR repositories"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "enable_image_scanning" {
  description = "Enable image scanning for ECR repositories"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type for ECR repositories"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "Encryption type must be either AES256 or KMS."
  }
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images expire"
  type        = number
  default     = 1
  
  validation {
    condition     = var.untagged_image_expiry_days >= 1
    error_message = "Untagged image expiry days must be at least 1."
  }
}
