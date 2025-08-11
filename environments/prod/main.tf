#################################
# Groble Infrastructure - Production Environment
#################################
# 
# 이 파일은 groble 애플리케이션의 프로덕션 환경을 위한 Terraform 설정입니다.
# 
# 프로젝트 구조:
# - Infrastructure Layer: VPC, 네트워크, 보안 그룹, Load Balancer, IAM 역할, Route53
# - Platform Layer: ECS Cluster, ECR, CodeDeploy
# - Service Layer: API Service, MySQL Service, Redis Service

#################################
# Infrastructure Layer 모듈 호출
#################################

# VPC 및 네트워크 인프라
module "vpc" {
  source = "../../modules/infrastructure/vpc"
  
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  project_name         = var.project_name
}

# 보안 그룹 인프라
module "security_groups" {
  source = "../../modules/infrastructure/security-groups"
  
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  project_name = var.project_name
  trusted_ips  = var.trusted_ips
}

# IAM 역할 인프라
module "iam_roles" {
  source = "../../modules/infrastructure/iam-roles"
  
  project_name = var.project_name
}

# Load Balancer 인프라
module "load_balancer" {
  source = "../../modules/infrastructure/load-balancer"
  
  vpc_id                        = module.vpc.vpc_id
  public_subnet_ids             = module.vpc.public_subnet_ids
  load_balancer_sg_id           = module.security_groups.load_balancer_sg_id
  project_name                  = var.project_name
  enable_deletion_protection    = var.enable_deletion_protection
  health_check_path             = var.health_check_path
  ssl_certificate_arn           = var.ssl_certificate_arn
  additional_ssl_certificate_arn = var.additional_ssl_certificate_arn
  idle_timeout                  = 300
}

# Route53 DNS 인프라
module "route53" {
  source = "../../modules/infrastructure/route53"
  
  load_balancer_dns_name = module.load_balancer.load_balancer_dns_name
  load_balancer_zone_id  = module.load_balancer.load_balancer_zone_id
}

#################################
# Platform Layer 모듈 호출
#################################

# ECS 클러스터 플랫폼
module "ecs_cluster" {
  source = "../../modules/platform/ecs-cluster"
  
  project_name                  = var.project_name
  enable_container_insights     = true
  
  # CloudWatch Logs 설정
  create_prod_logs              = true
  create_dev_logs               = false  # Production 환경에서는 dev 로그 생성 안함
  prod_log_retention_days       = 7
  dev_log_retention_days        = 3
  
  # Instance 생성 설정
  create_prod_instance          = true
  create_monitoring_instance    = true
  create_dev_instance           = false  # Production 환경에서는 dev 인스턴스 생성 안함
  
  # Instance 구성
  prod_instance_count           = var.prod_instance_count
  prod_instance_type            = var.prod_instance_type
  monitoring_instance_type      = var.monitoring_instance_type
  dev_instance_type             = "t3.small"  # 사용하지 않지만 기본값
  key_pair_name                 = var.key_pair_name
  
  # VPC 및 네트워크
  ubuntu_ami_id                 = module.vpc.ubuntu_ami_id
  public_subnet_ids             = module.vpc.public_subnet_ids
  
  # Security Groups
  prod_security_group_id        = module.security_groups.prod_target_group_sg_id
  monitoring_security_group_id  = module.security_groups.monitor_target_group_sg_id
  dev_security_group_id         = module.security_groups.develop_target_group_sg_id
  
  # IAM
  ecs_instance_profile_name     = module.iam_roles.ecs_instance_profile_name
  
  # Load Balancer
  monitoring_target_group_arn   = module.load_balancer.monitoring_target_group_arn
}

# ECR 컨테이너 레지스트리
module "ecr" {
  source = "../../modules/platform/ecr"
  
  project_name            = var.project_name
  create_prod_repository  = true
  create_dev_repository   = false  # Production 환경에서는 dev repository 생성 안함
  
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
    module.iam_roles.ecs_task_execution_role_arn,
    module.iam_roles.ecs_task_role_arn
  ]
}

#################################
# Service Layer 모듈 호출
#################################

# Production MySQL Service
module "mysql_service" {
  source = "../../modules/services/production/mysql-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = module.ecs_cluster.cluster_id
  ecs_task_execution_role_arn = module.iam_roles.ecs_task_execution_role_arn
  ecs_task_role_arn          = module.iam_roles.ecs_task_role_arn
  
  mysql_memory        = var.mysql_memory
  mysql_cpu          = var.mysql_cpu
  mysql_root_password = var.mysql_root_password
  mysql_database     = var.mysql_database
}

# Production Redis Service
module "redis_service" {
  source = "../../modules/services/production/redis-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = module.ecs_cluster.cluster_id
  ecs_task_execution_role_arn = module.iam_roles.ecs_task_execution_role_arn
  ecs_task_role_arn          = module.iam_roles.ecs_task_role_arn
  
  redis_memory   = var.redis_memory
  redis_cpu     = var.redis_cpu
  redis_password = var.redis_password
}

# Production API Service
module "api_service" {
  source = "../../modules/services/production/api-service"
  
  project_name                 = var.project_name
  ecs_cluster_id              = module.ecs_cluster.cluster_id
  ecs_task_execution_role_arn = module.iam_roles.ecs_task_execution_role_arn
  ecs_task_role_arn          = module.iam_roles.ecs_task_role_arn
  
  # Container 설정
  spring_app_image     = var.spring_app_image
  memory_reservation   = var.api_memory_reservation
  memory_limit        = var.api_memory_limit
  cpu                 = var.api_cpu
  desired_count       = var.api_desired_count
  
  # Application 설정
  spring_profiles = var.spring_profiles
  server_env     = var.server_env
  
  # Database 설정
  db_host             = module.ecs_cluster.prod_instance_private_ips[0]
  mysql_database      = var.mysql_database
  mysql_root_password = var.mysql_root_password
  
  # Redis 설정
  redis_host = module.ecs_cluster.prod_instance_private_ips[0]
  
  # Proxy 설정
  proxy_host = module.ecs_cluster.monitoring_instance_private_ip
  
  # Network 설정
  subnet_ids         = [module.vpc.public_subnet_ids[0]]  # ap-northeast-2a
  security_group_ids = [module.security_groups.api_task_sg_id]
  
  # Load Balancer 설정
  target_group_arn = module.load_balancer.prod_blue_target_group_arn
  
  depends_on = [
    module.mysql_service,
    module.redis_service
  ]
}

#################################
# CodeDeploy 배포 서비스
#################################

module "codedeploy" {
  source = "../../modules/platform/codedeploy"
  
  project_name                    = var.project_name
  create_prod_deployment_group    = true
  create_dev_deployment_group     = false  # Production 환경에서는 dev deployment group 생성 안함
  create_artifacts_bucket         = true
  
  # IAM Role
  codedeploy_service_role_arn     = module.iam_roles.codedeploy_service_role_arn
  
  # ECS 설정
  ecs_cluster_name                = module.ecs_cluster.cluster_name
  prod_service_name               = "${var.project_name}-prod-service"
  dev_service_name                = ""  # 사용하지 않음
  
  # Deployment Configuration
  prod_deployment_config          = var.deployment_config
  dev_deployment_config           = "CodeDeployDefault.ECSAllAtOnce"  # 사용하지 않음
  
  # Blue/Green 배포 설정
  deployment_ready_timeout_action = var.deployment_ready_timeout_action
  deployment_ready_wait_time      = var.deployment_ready_wait_time
  termination_wait_time           = var.termination_wait_time
  
  # Load Balancer 설정
  prod_blue_target_group_name     = module.load_balancer.prod_blue_target_group_name
  prod_green_target_group_name    = module.load_balancer.prod_green_target_group_name
  dev_blue_target_group_name      = ""  # 사용하지 않음
  dev_green_target_group_name     = ""  # 사용하지 않음
  prod_listener_arns              = [module.load_balancer.https_listener_arn]
  test_listener_arns              = [module.load_balancer.https_test_listener_arn]
  
  # 자동 롤백 설정
  enable_auto_rollback            = var.enable_auto_rollback
  auto_rollback_events            = var.auto_rollback_events
  
  # 알람 설정
  enable_alarm_configuration      = var.enable_alarm_configuration
  alarm_names                     = var.alarm_names
  
  depends_on = [
    module.api_service
  ]
}
