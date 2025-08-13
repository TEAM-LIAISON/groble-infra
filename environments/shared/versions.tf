terraform {
  required_version = ">= 1.0"
  
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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Groble Infrastructure"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedBy   = "jemin"
    }
  }
}
