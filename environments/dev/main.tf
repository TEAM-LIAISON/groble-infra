#################################
# Groble Infrastructure - Development Environment
#################################
# 
# 이 파일은 groble 애플리케이션의 개발 환경을 위한 Terraform 설정입니다.
# 
# 구조:
# - Shared 리소스는 data source로 참조 (VPC, IAM, Load Balancer 등)
# - DEV 전용 리소스만 이 환경에서 관리 (ECS Services)

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

data "aws_subnet" "dev_api_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  filter {
    name   = "availability-zone"
    values = ["ap-northeast-2c"]
  }
  filter {
    name   = "tag:Type"
    values = ["Public"]
  }
}

data "aws_security_group" "api_task_sg" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  filter {
    name   = "tag:Name"
    values = ["groble-api-task-sg"]  # 실제 API 전용 보안그룹 태그명에 맞게 수정
  }
}

data "aws_instance" "shared_dev_instance" {
  filter {
    name   = "tag:Name"
    values = ["groble-develop-instance"]  # shared 환경의 dev 인스턴스 태그명
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_instance" "shared_monitoring_instance" {
  filter {
    name   = "tag:Name"
    values = ["groble-monitoring-instance"]  # shared 환경의 monitoring 인스턴스 태그명
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
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

data "aws_lb_target_group" "shared_dev_blue_tg" {
  name = "groble-dev-blue-tg-v2"
}

data "aws_lb_target_group" "shared_dev_green_tg" {
  name = "groble-dev-green-tg-v2"
}

#################################
# DEV 전용 리소스
#################################

# DEV ECR 리포지토리
module "ecr" {
  source = "../../modules/platform/ecr"
  
  project_name            = var.project_name
  create_prod_repository  = false  # DEV 환경에서는 prod repository 생성 안함
  create_dev_repository   = true
  
  # ECR 설정
  image_tag_mutability    = "MUTABLE"
  enable_image_scanning   = true
  encryption_type         = "AES256"
  
  # Lifecycle 정책
  prod_max_image_count    = 10  # 사용하지 않지만 기본값
  dev_max_image_count     = var.dev_max_image_count
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
# DEV Service Layer
#################################

# Development MySQL Service
module "dev_mysql_service" {
  source = "../../modules/services/development/mysql-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = data.aws_ecs_cluster.shared_cluster.id
  ecs_task_execution_role_arn = data.aws_iam_role.shared_ecs_task_execution_role.arn
  ecs_task_role_arn          = data.aws_iam_role.shared_ecs_task_role.arn
  
  mysql_memory        = var.mysql_memory
  mysql_cpu          = var.mysql_cpu
  mysql_root_password = var.mysql_root_password
  mysql_database     = var.mysql_database
}

# Development Redis Service
module "dev_redis_service" {
  source = "../../modules/services/development/redis-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = data.aws_ecs_cluster.shared_cluster.id
  ecs_task_execution_role_arn = data.aws_iam_role.shared_ecs_task_execution_role.arn
  ecs_task_role_arn          = data.aws_iam_role.shared_ecs_task_role.arn
  
  redis_memory   = var.redis_memory
  redis_cpu     = var.redis_cpu
  redis_password = var.redis_password
}

# Development API Service
module "dev_api_service" {
  source = "../../modules/services/development/api-service"
  
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
  
  # Database 설정 (shared 환경의 DEV 인스턴스 IP 참조)
  db_host             = data.aws_instance.shared_dev_instance.private_ip
  mysql_database      = var.mysql_database
  mysql_root_password = var.mysql_root_password
  
  # Redis 설정 (shared 환경의 DEV 인스턴스 IP 참조)
  redis_host = data.aws_instance.shared_dev_instance.private_ip
  
  
  # Network 설정
  subnet_ids         = [data.aws_subnet.dev_api_subnet.id]  # 원래 사용하던 정확한 서브넷
  security_group_ids = [data.aws_security_group.api_task_sg.id]
  
  # Load Balancer 설정
  target_group_arn = data.aws_lb_target_group.shared_dev_blue_tg.arn
  
  depends_on = [
    module.dev_mysql_service,
    module.dev_redis_service
  ]
}

#################################
# 출력값 정의
#################################

# ECR outputs
output "ecr_repository_url" {
  description = "ECR repository URL for dev images"
  value       = module.ecr.dev_repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN for dev images"
  value       = module.ecr.dev_repository_arn
}

# API Service outputs
output "api_service_arn" {
  description = "API service ARN"
  value       = module.dev_api_service.service_arn
}

output "api_task_definition_arn" {
  description = "API task definition ARN"
  value       = module.dev_api_service.task_definition_arn
}

# MySQL Service outputs  
output "mysql_service_id" {
  description = "MySQL service ID"
  value       = module.dev_mysql_service.service_id
}

output "mysql_task_definition_arn" {
  description = "MySQL task definition ARN"
  value       = module.dev_mysql_service.task_definition_arn
}

# Redis Service outputs
output "redis_service_id" {
  description = "Redis service ID"
  value       = module.dev_redis_service.service_id
}

output "redis_task_definition_arn" {
  description = "Redis task definition ARN"
  value       = module.dev_redis_service.task_definition_arn
}
