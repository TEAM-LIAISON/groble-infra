# Groble Infrastructure - Shared Configuration

이 폴더는 Groble 인프라의 모든 환경에서 공통으로 사용되는 설정 파일들을 포함합니다.

## 📁 파일 구조

```
shared/
├── README.md           # 이 파일
├── providers.tf        # Terraform 프로바이더 공통 설정
├── variables.tf        # 공통 변수 정의
└── outputs.tf         # 공통 출력 정의
```

## 🎯 목적

- **일관성 유지**: 모든 환경에서 동일한 기본 설정 사용
- **중복 제거**: 공통 설정을 한 곳에서 관리
- **유지보수성**: 공통 변경사항을 한 번만 수정
- **표준화**: 프로젝트 전체의 명명 규칙과 태그 정책 통일

## 📋 파일별 설명

### providers.tf
- Terraform 및 AWS 프로바이더 버전 설정
- AWS 프로바이더 기본 설정 (프로파일, 리전, 태그)
- 공통 데이터 소스 (계정 정보, 리전 정보)
- 로컬 값들 (명명 규칙, 환경별 기본값)

### variables.tf
- 모든 환경에서 공통으로 사용되는 변수 정의
- 변수 검증 규칙 및 기본값 설정
- AWS 기본 설정, VPC 네트워크, 보안, SSL 인증서 관련 변수
- 애플리케이션 및 리소스 크기 관련 공통 변수

### outputs.tf
- 모든 환경에서 공통으로 사용되는 출력값 정의
- 네트워크, 보안 그룹, 로드 밸런서, IAM, ECS 관련 출력
- 환경별 조건부 출력 (Production/Development 전용)
- 서비스 및 환경 정보 출력

## 🔧 사용 방법

### 환경별 설정에서 참조
각 환경의 설정 파일에서 shared 폴더의 설정을 참조할 수 있습니다:

```hcl
# environments/prod/versions.tf 또는 environments/dev/versions.tf
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
}

# 공통 프로바이더 설정 참조
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
```

### 공통 변수 활용
```hcl
# environments/prod/main.tf 또는 environments/dev/main.tf
module "vpc" {
  source = "../../modules/infrastructure/vpc"
  
  # shared/variables.tf에서 정의된 공통 변수 사용
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  project_name         = var.project_name
}
```

## 🏗️ 공통 설정 항목

### 네트워크 설정
- **VPC CIDR**: `10.0.0.0/16`
- **가용 영역**: `ap-northeast-2a`, `ap-northeast-2c`
- **퍼블릭 서브넷**: `10.0.1.0/24`, `10.0.2.0/24`
- **프라이빗 서브넷**: `10.0.11.0/24`, `10.0.12.0/24`

### 프로젝트 설정
- **프로젝트명**: `groble`
- **AWS 리전**: `ap-northeast-2`
- **AWS 프로파일**: `groble-terraform`

### 공통 태그
- **Project**: "Groble Infrastructure"
- **ManagedBy**: "Terraform"
- **CreatedBy**: "jemin"
- **Environment**: 환경별로 동적 설정

### 리소스 명명 규칙
- **형식**: `{project_name}-{environment}-{resource_type}`
- **예시**: `groble-prod-cluster`, `groble-dev-api-service`

## 🔒 보안 고려사항

### 변수 검증
- 모든 중요한 변수에 대해 검증 규칙 적용
- CIDR 블록, ARN, 리전 형식 등 검증
- 최소/최대 값 제한 설정

### 기본값 보안
- 신뢰할 수 있는 IP만 SSH 접근 허용 권장
- SSL 인증서 ARN 검증
- 강력한 패스워드 정책 적용

## 📝 변경 가이드

### 공통 설정 변경
1. `shared/` 폴더의 해당 파일 수정
2. 모든 환경에 영향을 주므로 신중히 검토
3. 각 환경에서 테스트 후 적용

### 환경별 오버라이드
```hcl
# environments/prod/terraform.tfvars
# shared 설정을 오버라이드하여 환경별 값 설정
project_name = "groble"
vpc_cidr = "10.0.0.0/16"  # shared 기본값과 동일
enable_deletion_protection = true  # 프로덕션에서만 활성화
```

## 🚀 향후 개선사항

### 원격 상태 관리
```hcl
# shared/providers.tf에서 주석 해제하여 활성화
backend "s3" {
  bucket         = "groble-terraform-state"
  key            = "environments/${var.environment}/terraform.tfstate"
  region         = "ap-northeast-2"
  encrypt        = true
  dynamodb_table = "groble-terraform-locks"
}
```

### 환경별 워크스페이스
```bash
# Terraform 워크스페이스를 활용한 환경 분리
terraform workspace new prod
terraform workspace new dev
terraform workspace select prod
```

## 🔍 모니터링 및 로깅

### 공통 모니터링 설정
- CloudWatch Container Insights 기본 활성화
- 환경별 로그 보관 기간 설정
- 공통 메트릭 및 대시보드 설정

### 비용 최적화
- 환경별 리소스 크기 자동 조정
- 개발 환경 리소스 최소화
- 태그 기반 비용 추적 활성화
