# VPC 관련 변수
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

# 프로젝트 관련 변수
variable "project_name" {
  description = "Name of the project"
  type        = string
}

# SSH 접근 관련 변수
variable "trusted_ips" {
  description = "List of trusted IP addresses for SSH access"
  type        = list(string)
  
  validation {
    condition     = length(var.trusted_ips) > 0
    error_message = "At least one trusted IP must be specified."
  }
}
