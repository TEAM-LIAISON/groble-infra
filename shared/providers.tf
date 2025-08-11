#################################
# Shared Providers Configuration for Groble Infrastructure
#################################
# 
# 이 파일은 모든 환경에서 공통으로 사용되는 Terraform과 AWS 프로바이더 설정을 정의합니다.
# 각 환경의 versions.tf에서 이 설정을 참조하여 일관성을 유지합니다.

#################################
# Terraform 버전 및 필수 프로바이더
#################################

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
  
  # 향후 원격 상태 관리를 위한 백엔드 설정 (주석 처리)
  # backend "s3" {
  #   bucket         = "groble-terraform-state"
  #   key            = "environments/${var.environment}/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   encrypt        = true
  #   dynamodb_table = "groble-terraform-locks"
  # }
}

#################################
# AWS 프로바이더 기본 설정
#################################

provider "aws" {
  profile = "groble-terraform"
  region  = var.aws_region
  
  # 모든 리소스에 기본 태그 적용
  default_tags {
    tags = merge(var.common_tags, {
      Environment = var.environment
      Region      = var.aws_region
    })
  }
}

#################################
# Random 프로바이더 설정
#################################

provider "random" {
  # Random 프로바이더는 별도 설정이 필요하지 않습니다.
}

#################################
# 데이터 소스 - 현재 AWS 계정 정보
#################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

#################################
# 로컬 값들
#################################

locals {
  # 계정 정보
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # 리소스 명명 규칙
  name_prefix = "${var.project_name}-${var.environment}"
  
  # 공통 태그
  common_tags = merge(var.common_tags, {
    Environment = var.environment
    Region      = local.region
    AccountId   = local.account_id
  })
  
  # DNS 도메인 설정
  domain_name = var.environment == "prod" ? "groble.im" : "dev.groble.im"
  api_domain  = var.environment == "prod" ? "api.groble.im" : "api.dev.groble.im"
  
  # 환경별 설정
  is_production = var.environment == "prod"
  is_development = var.environment == "dev"
  
  # 리소스 크기 설정 (환경별 기본값)
  instance_types = {
    prod = {
      api        = "t3.small"
      monitoring = "t3.small"
    }
    dev = {
      api        = "t3.small"
      monitoring = "t3.micro"
    }
  }
  
  # 컨테이너 리소스 설정 (환경별 기본값)
  container_resources = {
    prod = {
      mysql_memory = 500
      mysql_cpu    = 256
      redis_memory = 128
      redis_cpu    = 128
      api_memory   = 700
      api_cpu      = 256
    }
    dev = {
      mysql_memory = 256
      mysql_cpu    = 128
      redis_memory = 128
      redis_cpu    = 128
      api_memory   = 700
      api_cpu      = 256
    }
  }
  
  # ECR 설정 (환경별)
  ecr_settings = {
    prod = {
      max_image_count = 10
      tag_prefixes    = ["v", "release", "prod"]
    }
    dev = {
      max_image_count = 5
      tag_prefixes    = ["v", "dev", "feature", "main"]
    }
  }
  
  # 로그 보관 기간 (환경별)
  log_retention_days = {
    prod = 7
    dev  = 3
  }
}

#################################
# 출력 - 공통 정보
#################################

output "account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "region" {
  description = "AWS Region"
  value       = local.region
}

output "name_prefix" {
  description = "Resource name prefix"
  value       = local.name_prefix
}

output "domain_name" {
  description = "Domain name for the environment"
  value       = local.domain_name
}

output "api_domain" {
  description = "API domain name for the environment"
  value       = local.api_domain
}

output "is_production" {
  description = "Whether this is a production environment"
  value       = local.is_production
}

output "is_development" {
  description = "Whether this is a development environment"
  value       = local.is_development
}
