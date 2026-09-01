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
  backend = "s3"

  config = {
    bucket  = "groble-terraform-state"
    key     = "environments/shared/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "groble-terraform"
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
    values = ["Private"]
  }
}

# Phase 5 — DB 서브넷 그룹용. RDS 는 서로 다른 AZ 의 서브넷 2개 이상을 요구하므로
# 위 dev_api_subnet(2c 단일)로는 만들 수 없다.
# 인스턴스 자체는 rds_availability_zone 으로 2c 에 고정한다.
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

# Shared 환경의 Load Balancer Target Group 참조
data "aws_lb_target_group" "shared_dev_blue_tg" {
  name = "groble-dev-blue-tg-v2"
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
# Phase 5 — DEV RDS MySQL
#################################
# docs/runbook/phase-05-dev-rds.md
#
# prod 와 **같은 모듈**을 쓴다. dev 를 prod 와 같은 형태로 만드는 것이 Phase 8 의 목적이라
# 모듈을 가르면 §3-5 promote 게이트가 검증하는 것이 줄어든다.
#
# ⚠️ 이 시점에는 앱이 아직 컨테이너 MySQL 을 본다. db_host 전환은 컷오버(C단계)다.
module "dev_rds_mysql" {
  source = "../../modules/infrastructure/rds-mysql"

  project_name          = var.project_name
  environment           = "dev"
  private_subnet_ids    = data.aws_subnets.shared_private_subnets.ids
  rds_security_group_id = data.terraform_remote_state.shared.outputs.rds_mysql_dev_security_group_id

  # ⚠️ 반드시 넘긴다. 생략하면 prod 가 쓰는 "groble-mysql-subnet-group" 과
  #    이름이 충돌해 DBSubnetGroupAlreadyExists 로 apply 가 죽는다.
  db_subnet_group_name = "${var.project_name}-dev-mysql-subnet-group"

  # prod 의 8.0 시절 잔재를 dev 에까지 복제하지 않는다.
  create_legacy_80_parameter_group = false

  # RDS 설정 — 엔진 버전(8.4.11)은 모듈에 고정되어 있다. prod 와 같아지는 지점이다.
  instance_class    = var.rds_instance_class
  database_name     = var.mysql_database
  database_username = "groble_root"
  database_password = var.mysql_root_password

  # Storage 설정
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  # Backup 설정 — ⚠️ 값은 UTC 다. 모듈 기본값은 한국 근무시간이라 반드시 명시한다
  backup_retention_period = var.rds_backup_retention_period
  backup_window           = var.rds_backup_window
  maintenance_window      = var.rds_maintenance_window

  # 가용성 — dev 노드(2c)와 정렬해 cross-AZ 를 없앤다
  multi_az          = var.rds_multi_az
  availability_zone = var.rds_availability_zone

  # 보안 설정
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot
}

# Phase 5 — Dev RDS 알람
# 통지 경로(SNS)는 shared 에서 만든 dev 채널 토픽(#groble-alert-dev)을 쓴다.
module "rds_alarms" {
  source = "../../modules/observability/rds-alarms"

  project_name = var.project_name
  environment  = "dev"

  # ⚠️ rds_instance_id 가 아니다. aws_db_instance.id 는 DBInstanceIdentifier 가 아니라
  #    DbiResourceId 를 반환하므로, 그 값을 쓰면 존재하지 않는 지표를 감시하게 된다
  #    (에러 없이 조용히 실패한다). 모듈 outputs.tf 의 경고 참조.
  db_instance_identifier = module.dev_rds_mysql.rds_instance_identifier

  alarm_actions = [data.terraform_remote_state.shared.outputs.alerts_sns_topic_arn_dev]
  ok_actions    = [data.terraform_remote_state.shared.outputs.alerts_sns_topic_arn_dev]
}

#################################
# DEV Service Layer
#################################

# Development MySQL Service — Phase 5 E단계(2026-09-01)에서 제거했다.
# dev DB 는 module.dev_rds_mysql (RDS MySQL 8.4.11) 로 이관됐다.
# 노드의 /opt/mysql-dev-data 는 남아 있으며 Phase 9 의 노드 교체에서 사라진다.
# docs/runbook/phase-05-dev-rds.md

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
  #
  # Phase 5 컷오버(C2), 2026-09-01 — 컨테이너 IP → RDS 로 전환했다.
  #    되돌리려면 data.aws_instance.shared_dev_instance.private_ip (10.0.12.215)
  #
  #    apply 는 태스크 정의 리비전만 등록하고 배포하지 않는다
  #    (lifecycle { ignore_changes = [task_definition] }).
  #    다만 그 리비전이 버려지는 것은 아니다 — 앱 CD 워크플로가
  #    describe-task-definition <family>(리비전 미지정 = 최신 ACTIVE)를 읽어
  #    이미지만 갈아끼우므로, **다음 배포에 이 값이 실려 간다.**
  #
  #    ⚠️ 그래서 apply 전에 terraform.tfvars 의 spring_app_image 를 실행 중
  #       이미지와 맞춰야 한다. 낡은 값이면 그것이 family 의 최신 리비전이 되어
  #       이미지를 갈아끼우지 않는 배포(롤백·재배포)가 낡은 이미지를 띄운다.
  #    ⚠️ apply 는 데이터 복원 뒤에 한다. 먼저 하면 그 사이의 배포가
  #       빈 RDS 를 보게 된다.
  #    docs/runbook/phase-05-dev-rds.md
  db_host             = module.dev_rds_mysql.rds_address
  mysql_database      = var.mysql_database
  mysql_root_password = var.mysql_root_password
  
  # Redis 설정 (shared 환경의 DEV 인스턴스 IP 참조)
  redis_host = data.aws_instance.shared_dev_instance.private_ip
  
  # OpenTelemetry 설정
  # Phase 4 — 모니터링 노드 IP 가 아니라 이름을 본다 (계획서 §2.4).
  # 노드를 교체할 때 이 값을 바꾸지 않는다 — Route 53 레코드만 바꾸면 60초 안에 옮겨간다.
  otel_exporter_endpoint = "http://${data.terraform_remote_state.shared.outputs.otel_endpoint_fqdn}:4318"
  
  # Network 설정
  subnet_ids         = [data.aws_subnet.dev_api_subnet.id]  # dev API service Private 서브넷 (NAT instance 경유)
  security_group_ids = [data.aws_security_group.api_task_sg.id]
  
  # Load Balancer 설정
  target_group_arn = data.aws_lb_target_group.shared_dev_blue_tg.arn
  
  depends_on = [
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

# Redis Service outputs
output "redis_service_id" {
  description = "Redis service ID"
  value       = module.dev_redis_service.service_id
}

output "redis_task_definition_arn" {
  description = "Redis task definition ARN"
  value       = module.dev_redis_service.task_definition_arn
}

# Phase 5 — RDS outputs
output "dev_rds_endpoint" {
  description = "Dev RDS MySQL 엔드포인트 (host:port)"
  value       = module.dev_rds_mysql.rds_endpoint
}

output "dev_rds_address" {
  description = "Dev RDS MySQL 주소. 컷오버 시 태스크 정의의 DB_HOST 가 될 값"
  value       = module.dev_rds_mysql.rds_address
}

output "dev_rds_instance_identifier" {
  description = "Dev RDS 인스턴스 식별자 (CloudWatch DBInstanceIdentifier 차원 값)"
  value       = module.dev_rds_mysql.rds_instance_identifier
}
