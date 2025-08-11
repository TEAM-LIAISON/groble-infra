variable "project_name" {
  description = "Project name"
  type        = string
}

# Repository 생성 여부
variable "create_prod_repository" {
  description = "Create production ECR repository"
  type        = bool
  default     = true
}

variable "create_dev_repository" {
  description = "Create development ECR repository"
  type        = bool
  default     = true
}

# ECR 기본 설정
variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "enable_image_scanning" {
  description = "Enable image scanning on push"
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

# Lifecycle 정책 설정
variable "prod_max_image_count" {
  description = "Maximum number of images to keep in production repository"
  type        = number
  default     = 10
}

variable "dev_max_image_count" {
  description = "Maximum number of images to keep in development repository"
  type        = number
  default     = 10
}

variable "prod_tag_prefixes" {
  description = "Tag prefixes for production images"
  type        = list(string)
  default     = ["v", "release", "prod"]
}

variable "dev_tag_prefixes" {
  description = "Tag prefixes for development images"
  type        = list(string)
  default     = ["v", "dev", "feature", "main"]
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images expire"
  type        = number
  default     = 1
}

# IAM 권한 설정
variable "allowed_principals" {
  description = "List of AWS principals allowed to access ECR repositories"
  type        = list(string)
}
