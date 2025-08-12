#################################
# Groble Infrastructure - Production Environment
#################################
# 
# 이 파일은 groble 애플리케이션의 프로덕션 환경을 위한 Terraform 설정입니다.
# 
# 구조:
# - Shared 리소스는 data source로 참조 (VPC, IAM, Load Balancer 등)
# - PROD 전용 리소스만 이 환경에서 관리 (ECR, ECS Services)

#################################
# Shared 리소스 참조 (Data Sources)
#################################

# Shared 환경의 Terraform State 참조
data "terraform_remote_state" "shared" {
  backend = "local"

  config = {
    path = "../shared/terraform.tfstate"
  }
}

# 또는 직접 리소스 참조 (local backend 사용 시)
data "aws_vpc" "shared_vpc" {
  filter {
    name   = "tag:Name"
    values = ["groble-vpc"]
  }
}

data "aws_subnets" "shared_public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["Public"]
  }
}

data "aws_subnet" "prod_api_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  filter {
    name   = "availability-zone"
    values = ["ap-northeast-2a"]
  }
  filter {
    name   = "tag:Type"
    values = ["Public"]
  }
}

data "aws_security_group" "shared_api_task_sg" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  filter {
    name   = "tag:Name"
    values = ["groble-api-task-sg"]  # 실제 API 전용 보안그룹 태그명에 맞게 수정
  }
}

data "aws_iam_role" "shared_ecs_task_execution_role" {
  name = "groble-ecs-task-execution-role"
}

data "aws_iam_role" "shared_ecs_task_role" {
  name = "groble-ecs-task-role"
}

data "aws_ecs_cluster" "shared_cluster" {
  cluster_name = "groble-cluster"
}

data "aws_lb" "shared_load_balancer" {
  name = "groble-load-balancer"
}

data "aws_lb_target_group" "shared_prod_blue_tg" {
  name = "groble-prod-blue-tg-v2"
}

data "aws_lb_target_group" "shared_prod_green_tg" {
  name = "groble-prod-green-tg-v2"
}

#################################
# PROD 전용 리소스
#################################

# PROD ECR 리포지토리
module "ecr" {
  source = "../../modules/platform/ecr"
  
  project_name            = var.project_name
  create_prod_repository  = true  
  create_dev_repository   = false  # PROD 환경에서는 dev repository 생성 안함
  
  # ECR 설정
  image_tag_mutability    = "MUTABLE"
  enable_image_scanning   = true
  encryption_type         = "AES256"
  
  # Lifecycle 정책
  prod_max_image_count    = var.prod_max_image_count  # 존재하는지 확인
  dev_max_image_count     = 10  # 사용하지 않지만 기본값
  prod_tag_prefixes       = ["v", "release", "prod"]
  dev_tag_prefixes        = ["v", "dev", "feature", "main"]
  untagged_image_expiry_days = 1
  
  # IAM 권한
  allowed_principals = [
    data.aws_iam_role.shared_ecs_task_execution_role.arn,
    data.aws_iam_role.shared_ecs_task_role.arn
  ]
}

#################################
# PROD Service Layer
#################################

# Production MySQL Service
module "mysql_service" {
  source = "../../modules/services/production/mysql-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = data.aws_ecs_cluster.shared_cluster.id
  ecs_task_execution_role_arn = data.aws_iam_role.shared_ecs_task_execution_role.arn
  ecs_task_role_arn          = data.aws_iam_role.shared_ecs_task_role.arn
  
  mysql_memory        = var.mysql_memory
  mysql_cpu          = var.mysql_cpu
  mysql_root_password = var.mysql_root_password
  mysql_database     = var.mysql_database
}

# Production Redis Service
module "redis_service" {
  source = "../../modules/services/production/redis-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = data.aws_ecs_cluster.shared_cluster.id
  ecs_task_execution_role_arn = data.aws_iam_role.shared_ecs_task_execution_role.arn
  ecs_task_role_arn          = data.aws_iam_role.shared_ecs_task_role.arn
  
  redis_memory   = var.redis_memory
  redis_cpu     = var.redis_cpu
  redis_password = var.redis_password
}

# Production API Service
module "api_service" {
  source = "../../modules/services/production/api-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = data.aws_ecs_cluster.shared_cluster.id
  ecs_task_execution_role_arn = data.aws_iam_role.shared_ecs_task_execution_role.arn
  ecs_task_role_arn          = data.aws_iam_role.shared_ecs_task_role.arn
  
  # Container 설정
  spring_app_image     = var.spring_app_image
  memory_reservation   = var.api_memory_reservation
  memory_limit        = var.api_memory_limit
  cpu                 = var.api_cpu
  desired_count       = var.api_desired_count
  
  # Application 설정
  spring_profiles = var.spring_profiles
  server_env     = var.server_env
  
  # Database 설정 (shared 환경의 PROD 인스턴스 IP 참조)
  db_host             = "10.0.1.150"  # TODO: data source로 prod instance IP 참조
  mysql_database      = var.mysql_database
  mysql_root_password = var.mysql_root_password
  
  # Redis 설정 (shared 환경의 PROD 인스턴스 IP 참조)
  redis_host = "10.0.1.150"  # TODO: data source로 prod instance IP 참조
  
  # Proxy 설정 (shared 환경의 monitoring 인스턴스 IP 참조)
  proxy_host = "10.0.1.200"  # TODO: data source로 monitoring instance IP 참조
  
  # Network 설정
  subnet_ids         = [data.aws_subnet.prod_api_subnet.id]  # prod 인스턴스 Public 서브넷
  security_group_ids = [data.aws_security_group.shared_api_task_sg.id]       # 현재 사용 중인 보안 그룹
  
  # Load Balancer 설정 - 현재 활성 target group 사용 (CodeDeploy 관리)
  target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-2:538827147369:targetgroup/groble-prod-green-tg-v2/9397bc43a431afe3"
  
  depends_on = [
    module.mysql_service,
    module.redis_service
  ]
}

#################################
# 출력값 정의
#################################

# ECR outputs - 루트 리소스 직접 참조
output "ecr_repository_url" {
  description = "ECR repository URL for prod images"
  value       = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-prod-spring-api"
}

output "ecr_repository_arn" {
  description = "ECR repository ARN for prod images"
  value       = "arn:aws:ecr:ap-northeast-2:538827147369:repository/groble-prod-spring-api"
}

# API Service outputs
output "api_service_arn" {
  description = "API service ARN"
  value       = module.api_service.service_arn
}

output "api_task_definition_arn" {
  description = "API task definition ARN"
  value       = module.api_service.task_definition_arn
}

# MySQL Service outputs  
output "mysql_service_id" {
  description = "MySQL service ID"
  value       = module.mysql_service.service_id
}

output "mysql_task_definition_arn" {
  description = "MySQL task definition ARN"
  value       = module.mysql_service.task_definition_arn
}

# Redis Service outputs
output "redis_service_id" {
  description = "Redis service ID"
  value       = module.redis_service.service_id
}

output "redis_task_definition_arn" {
  description = "Redis task definition ARN"
  value       = module.redis_service.task_definition_arn
}
