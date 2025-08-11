# VPC 관련 변수
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

# Security Group 관련 변수
variable "load_balancer_sg_id" {
  description = "ID of the load balancer security group"
  type        = string
}

# 프로젝트 관련 변수
variable "project_name" {
  description = "Name of the project"
  type        = string
}

# Load Balancer 설정 변수
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 300
}

# 헬스체크 관련 변수
variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

# SSL 인증서 관련 변수
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  
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
