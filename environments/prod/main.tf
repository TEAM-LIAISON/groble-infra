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

data "aws_subnets" "shared_private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["Private"]
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
    values = ["Private"]
  }
}

data "aws_security_group" "shared_api_task_sg" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
  filter {
    name   = "tag:Name"
    values = ["groble-api-task-sg"]
  }
}

# RDS 보안 그룹은 terraform remote state에서 참조

# Shared 환경의 EC2 인스턴스들 참조
data "aws_instance" "shared_prod_instance" {
  filter {
    name   = "tag:Name"
    values = ["groble-prod-instance-1"]  # shared 환경의 prod 인스턴스 태그명
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

# Shared 환경의 Load Balancer Target Group 참조
data "aws_lb_target_group" "shared_prod_blue_tg" {
  name = "groble-prod-blue-tg-v2"
}

data "aws_lb" "shared_load_balancer" {
  name = "groble-load-balancer"
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
  prod_max_image_count    = var.prod_max_image_count
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
# PROD RDS MySQL
#################################

# Production RDS MySQL Instance
module "rds_mysql" {
  source = "../../modules/infrastructure/rds-mysql"
  
  project_name           = var.project_name
  environment            = "prod"
  private_subnet_ids     = data.aws_subnets.shared_private_subnets.ids
  rds_security_group_id  = data.terraform_remote_state.shared.outputs.rds_mysql_security_group_id
  
  # RDS 설정
  instance_class         = var.rds_instance_class
  database_name          = var.mysql_database
  database_username      = "groble_root"
  database_password      = var.mysql_root_password
  
  # Storage 설정
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage
  
  # Backup 설정
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = var.rds_backup_window
  maintenance_window     = var.rds_maintenance_window
  
  # 고가용성 설정
  multi_az               = var.rds_multi_az
  
  # 보안 설정
  deletion_protection    = var.rds_deletion_protection
  skip_final_snapshot    = var.rds_skip_final_snapshot
}

#################################
# PROD Service Layer
#################################

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
  
  # Database 설정 - RDS MySQL 엔드포인트 사용
  db_host             = module.rds_mysql.rds_address
  mysql_database      = var.mysql_database
  mysql_root_password = var.mysql_root_password
  
  # Redis 설정 - data source로 참조
  redis_host = data.aws_instance.shared_prod_instance.private_ip
  
  # OpenTelemetry 설정 (monitoring 인스턴스 IP 참조)
  otel_exporter_endpoint = "http://${data.aws_instance.shared_monitoring_instance.private_ip}:4318"
  
  # Network 설정
  subnet_ids         = [data.aws_subnet.prod_api_subnet.id]  # prod API service Private 서브넷 (NAT instance 경유)
  security_group_ids = [data.aws_security_group.shared_api_task_sg.id]       # 현재 사용 중인 보안 그룹
  
  # Load Balancer 설정
  target_group_arn = data.aws_lb_target_group.shared_prod_blue_tg.arn
  
  depends_on = [
    module.rds_mysql,
    module.redis_service
  ]
}

# Note: MySQL service removed - using RDS MySQL instead

#################################
# 출력값 정의
#################################

# ECR outputs
output "ecr_repository_url" {
  description = "ECR repository URL for prod images"
  value       = module.ecr.prod_repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN for prod images"
  value       = module.ecr.prod_repository_arn
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

# Redis Service outputs
output "redis_service_id" {
  description = "Redis service ID"
  value       = module.redis_service.service_id
}

output "redis_task_definition_arn" {
  description = "Redis task definition ARN"
  value       = module.redis_service.task_definition_arn
}

# RDS MySQL outputs
output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = module.rds_mysql.rds_endpoint
}

output "rds_address" {
  description = "RDS MySQL address"
  value       = module.rds_mysql.rds_address
}

output "rds_instance_id" {
  description = "RDS MySQL instance ID"
  value       = module.rds_mysql.rds_instance_id
}
