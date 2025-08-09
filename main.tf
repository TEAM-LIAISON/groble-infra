#################################
# Groble Infrastructure - Main Configuration
#################################
# 
# 이 파일은 groble 애플리케이션을 위한 AWS 인프라 관리용 Terraform 설정입니다.
# 
# 프로젝트 구조:
# - VPC 및 네트워크 (01-vpc.tf)
# - 보안 그룹 (02-security-groups.tf)  
# - Application Load Balancer (03-load-balancer.tf)
# - IAM 역할 및 권한 (04-iam-roles.tf)
# - ECS 클러스터 및 태스크 정의 (05-ecs-cluster.tf)
# - EC2 인스턴스 (06-ec2-instances.tf)
# - ECS 서비스 (07-ecs-services.tf)
# - CodeDeploy Blue/Green 배포 (08-codedeploy.tf)
# - ECR 컨테이너 레지스트리 (09-ecr.tf)
# - Route 53 DNS 레코드 (10-route53.tf)

#################################

#################################
# 현재 배포 단계 및 상태
#################################

# 배포 완료된 단계:
# ✅ 01-vpc.tf - VPC, 서브넷, 라우팅 테이블
# ✅ 02-security-groups.tf - 모든 보안 그룹
# ✅ 03-load-balancer.tf - ALB, 타겟 그룹, 리스너
# ✅ 04-iam-roles.tf - ECS, CodeDeploy IAM 역할
# ✅ 05-ecs-cluster.tf - ECS 클러스터, 태스크 정의, 서비스 디스커버리
# ✅ 06-ec2-instances.tf - EC2 인스턴스 (프로덕션, 개발, 모니터링)
# ✅ 07-ecs-services.tf - ECS 서비스들 (MySQL, Redis, Spring API)
# ✅ 08-codedeploy.tf - CodeDeploy Blue/Green 배포
# ✅ 09-ecr.tf - ECR 컨테이너 레지스트리
# ✅ 10-route53.tf - Route 53 DNS 레코드

# 🚀 전체 인프라 배포 완료 상태!

#################################
# 인프라 아키텍처 설명
#################################

# 네트워크 구성:
# - VPC: 10.0.0.0/16
# - 퍼블릭 서브넷: 10.0.1.0/24 (ap-northeast-2a), 10.0.2.0/24 (ap-northeast-2c)
# - 프라이빗 서브넷: 10.0.11.0/24 (ap-northeast-2a), 10.0.12.0/24 (ap-northeast-2c)

# 컴퓨팅 리소스:
# - ECS 클러스터: groble-cluster
# - 프로덕션 인스턴스: t3.small × 1 (퍼블릭 서브넷)
# - 개발 인스턴스: t3.small × 1 (퍼블릭 서브넷)  
# - 모니터링 인스턴스: t3.micro × 1 (퍼블릭 서브넷)

# 컨테이너 서비스:
# - Production: MySQL 8.0, Redis 7, Spring Boot API
# - Development: MySQL 8.0, Redis 7, Spring Boot API

# 로드 밸런싱:
# - Application Load Balancer (인터넷 연결)
# - Blue/Green 배포 지원 타겟 그룹
# - HTTPS 리다이렉트 및 SSL 종료
# - 도메인 기반 라우팅 (api.groble.im, api.dev.groble.im, monitor.groble.im)

# 배포 파이프라인:
# - CodeDeploy Blue/Green 배포
# - Production: 카나리 배포 (10% → 100%)
# - Development: 즉시 배포 (All at once)
# - ECR을 통한 컨테이너 이미지 관리

#################################
# 로컬 값 및 공통 태그
#################################

#locals {
#  common_tags = {
#    Project     = var.project_name
#    Environment = var.environment
#    Terraform   = "true"
#    CreatedBy   = "groble-infra"
#    ManagedBy   = "terraform"
#  }
#  
#  # 네트워크 정보
#  vpc_cidr = var.vpc_cidr
#  az_names = var.availability_zones
#  
#  # 환경별 설정
#  is_production = var.environment == "prod"
#  
#  # 컨테이너 이미지 정보
#  app_version = var.app_version != "" ? var.app_version : "latest"
#  
#  # 서비스 포트 정의
#  mysql_port = 3306
#  redis_port = 6379
#  spring_port = 8080
#  grafana_port = 3000
#  
#  # 도메인 정보
#  production_domain = "api.groble.im"
#  development_domain = "api.dev.groble.im"
#  monitoring_domain = "monitor.groble.im"
#  
#  # 데이터베이스 설정
#  mysql_prod_config = {
#    database = var.mysql_prod_database
#    password = var.mysql_prod_root_password
#    port     = local.mysql_port
#  }
#  
#  mysql_dev_config = {
#    database = var.mysql_dev_database
#    password = var.mysql_dev_root_password
#    port     = local.mysql_port
#  }
#  
#  # ECR 리포지토리 정보
#  ecr_repositories = {
#    production = "${var.project_name}-prod-spring-api"
#    development = "${var.project_name}-dev-spring-api"
#  }
#}

#################################
# 데이터 소스
#################################

# 현재 AWS 계정 정보
# data "aws_caller_identity" "current" {}

# 현재 리전 정보
# data "aws_region" "current" {}

# 현재 가용영역 정보
# data "aws_availability_zones" "available" {
#  state = "available"
# }

#################################
# 운영 가이드 및 주의사항
#################################

# 🎯 완전 배포 완료 상태!
# 
# 현재 모든 인프라가 배포되어 다음 서비스들이 실행 중입니다:
# 
# 1. 웹 서비스 접속:
#    - Production: https://groble.im
#    - Development: https://dev.groble.im
#    - Monitoring: https://monitor.groble.im
# 
# 2. 배포 파이프라인:
#    - ECR을 통한 Docker 이미지 관리
#    - CodeDeploy Blue/Green 자동 배포
#    - ALB를 통한 무중단 배포
# 
# 3. 데이터베이스 서비스:
#    - MySQL 8.0 (Production/Development 분리)
#    - Redis 7 (캐싱 서비스)
#    - 서비스 디스커버리를 통한 내부 통신
# 
# 4. 모니터링:
#    - Grafana 대시보드 (monitor.groble.im)
#    - ECS 컨테이너 상태 모니터링
#    - ALB 헬스체크
# 
# 5. 보안:
#    - HTTPS 강제 리다이렉트
#    - 보안 그룹을 통한 접근 제어
#    - IAM 역할 기반 권한 관리

#################################
# 중요한 운영 명령어
#################################

# 서비스 상태 확인:
# terraform output
# aws ecs list-services --cluster groble-cluster
# aws ec2 describe-instances --filters "Name=tag:Project,Values=groble"

# 컨테이너 상태 확인 (EC2 인스턴스 내부):
# ssh -i ~/.ssh/groble_prod_ec2_key_pair.pem ubuntu@<INSTANCE_IP>
# ./check-ecs-services.sh
# docker ps
# docker logs <container_id>

# 배포 상태 확인:
# aws codedeploy list-applications
# aws codedeploy list-deployment-groups --application-name groble-app

# ECR 이미지 관리:
# aws ecr describe-repositories
# aws ecr list-images --repository-name groble-prod-spring-api

#################################
# 비용 최적화 설정
#################################

# 현재 비용 절약을 위해 비활성화된 기능들:
# - CloudWatch 로그 (필요 시 활성화)
# - Container Insights (필요 시 활성화)
# - 자동 스케일링 (필요 시 추가)
# - RDS 대신 컨테이너 MySQL 사용

# 예상 월간 비용: ~$53 USD
# - ALB: $18
# - EC2 인스턴스: $30 (t3.small x2, t3.micro x1)
# - 데이터 전송: $5

#################################
# 백업 및 복구 가이드
#################################

# 중요한 데이터 백업:
# 1. terraform.tfstate 파일 (매일 백업 권장)
# 2. MySQL 데이터 (/opt/mysql-prod-data, /opt/mysql-dev-data)
# 3. ECR 이미지 (자동 라이프사이클 정책 적용)

# 백업 스크립트 실행:
# ./scripts/backup-terraform-state.sh
# ./scripts/backup-mysql-data.sh

#################################
# 보안 체크리스트
#################################

# ✅ 완료해야 할 보안 설정:
# 1. terraform.tfvars의 모든 패스워드 변경
# 2. trusted_ips를 실제 접속 IP로 제한
# 3. SSL 인증서 설정 (ACM)
# 4. SSH 키 페어 권한 설정 (chmod 400)
# 5. 정기적인 보안 패치 적용

#################################
# 모니터링 및 알림 설정
#################################

# 현재 활성화된 모니터링:
# - ALB 헬스체크
# - ECS 서비스 상태 모니터링
# - 컨테이너 헬스체크

# 추가 권장 모니터링 (필요 시):
# - CloudWatch 알람
# - SNS 알림
# - 로그 중앙화

#################################
# 성능 최적화 가이드
#################################

# 현재 설정:
# - Blue/Green 배포 (무중단 배포)
# - 컨테이너 리소스 제한

# 확장 시 고려사항:
# - ECS 서비스 오토 스케일링
# - RDS 마이그레이션
# - ElastiCache 도입
# - CloudFront CDN 적용

#################################
# 배포가이드
#################################

# Docker 이미지 빌드 및 배포:
# 1. 애플리케이션 빌드
# 2. ECR 로그인: aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <ECR_URI>
# 3. 이미지 빌드: docker build -t groble-prod-spring-api .
# 4. 이미지 태그: docker tag groble-prod-spring-api:latest <ECR_URI>/groble-prod-spring-api:latest
# 5. 이미지 푸시: docker push <ECR_URI>/groble-prod-spring-api:latest
# 6. CodeDeploy 배포 실행

# 로컬 개발 환경 설정:
# - 개발 환경 데이터베이스 접근
# - 환경 변수 설정

#################################
# 문제 해결 가이드
#################################

# 일반적인 문제들:
# 1. ECS 서비스 시작 실패 → 태스크 정의 및 리소스 확인
# 3. 배포 실패 → CodeDeploy 로그 확인
# 4. 데이터베이스 연결 실패 → 보안 그룹 및 환경 변수 확인

# 긴급 복구 절차:
# 1. 이전 terraform.tfstate 복원
# 2. Blue/Green 배포 롤백
# 3. 데이터베이스 백업 복원
# 4. 서비스 수동 재시작