terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = "groble-terraform"
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = "Groble Infrastructure"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedBy   = "jemin"
    }
  }
}

# AWS Chatbot 전용 별칭.
# Chatbot은 API 엔드포인트가 us-east-2에만 존재하는 서비스라, 기본 프로바이더
# (ap-northeast-2)로는 호출 자체가 실패한다. 이 별칭은 Chatbot 설정에만 쓰이며
# SNS 토픽·알람 등 나머지 리소스는 전부 ap-northeast-2에 그대로 생성된다.
provider "aws" {
  alias   = "chatbot"
  profile = "groble-terraform"
  region  = "us-east-2"

  default_tags {
    tags = {
      Project     = "Groble Infrastructure"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedBy   = "jemin"
    }
  }
}