# Terraform 및 AWS 프로바이더 설정
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS 프로바이더 설정
provider "aws" {
  region = var.aws_region
  
  # 모든 리소스에 기본 태그 적용
  default_tags {
    tags = {
      Project     = "Groble Infrastructure"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedBy   = "jemin"
    }
  }
}
