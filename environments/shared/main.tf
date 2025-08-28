#################################
# Groble Infrastructure - Shared Environment
#################################
# 
# 이 파일은 groble 애플리케이션의 공유 인프라를 위한 Terraform 설정입니다.
# DEV와 PROD 환경에서 공통으로 사용하는 리소스들을 관리합니다.
# 
# 공유 리소스:
# - Infrastructure Layer: VPC, 네트워크, 보안 그룹, Load Balancer, IAM 역할, Route53
# - Platform Layer: ECS Cluster, CodeDeploy

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

# ECS 클러스터 플랫폼 (공통 인프라만)
module "ecs_cluster" {
  source = "../../modules/platform/ecs-cluster"
  
  project_name                  = var.project_name
  enable_container_insights     = false
  
  # CloudWatch Logs 설정 (비활성화)
  create_prod_logs              = false
  create_dev_logs               = false
  prod_log_retention_days       = 7
  dev_log_retention_days        = 3
  
  # Instance 생성 설정
  create_prod_instance          = true
  create_monitoring_instance    = true
  create_dev_instance           = true
  
  # Instance 구성
  prod_instance_count           = var.prod_instance_count
  prod_instance_type            = var.prod_instance_type
  monitoring_instance_type      = var.monitoring_instance_type
  dev_instance_type             = var.dev_instance_type
  key_pair_name                 = var.key_pair_name
  
  # VPC 및 네트워크
  ubuntu_ami_id                 = module.vpc.ubuntu_ami_id
  public_subnet_ids             = module.vpc.public_subnet_ids
  private_subnet_ids            = module.vpc.private_subnet_ids
  
  # Security Groups
  prod_security_group_id        = module.security_groups.prod_target_group_sg_id
  monitoring_security_group_id  = module.security_groups.monitor_target_group_sg_id
  dev_security_group_id         = module.security_groups.develop_target_group_sg_id
  
  # IAM
  ecs_instance_profile_name     = module.iam_roles.ecs_instance_profile_name
  
  # Load Balancer
  monitoring_target_group_arn   = module.load_balancer.monitoring_target_group_arn
  
  # Route Tables
  private_route_table_id        = module.vpc.private_route_table_id
}

#################################
# CodeDeploy 배포 서비스 (공통 설정)
#################################

module "codedeploy" {
  source = "../../modules/platform/codedeploy"
  
  project_name                    = var.project_name
  create_prod_deployment_group    = true
  create_dev_deployment_group     = true
  create_artifacts_bucket         = true
  
  # IAM Role
  codedeploy_service_role_arn     = module.iam_roles.codedeploy_service_role_arn
  
  # ECS 설정
  ecs_cluster_name                = module.ecs_cluster.cluster_name
  prod_service_name               = "${var.project_name}-prod-service"
  dev_service_name                = "${var.project_name}-dev-service"
  
  # Deployment Configuration
  prod_deployment_config          = var.prod_deployment_config
  dev_deployment_config           = var.dev_deployment_config
  
  # Blue/Green 배포 설정
  deployment_ready_timeout_action = var.deployment_ready_timeout_action
  deployment_ready_wait_time      = var.deployment_ready_wait_time
  termination_wait_time           = var.termination_wait_time
  
  # Load Balancer 설정
  prod_blue_target_group_name     = module.load_balancer.prod_blue_target_group_name
  prod_green_target_group_name    = module.load_balancer.prod_green_target_group_name
  dev_blue_target_group_name      = module.load_balancer.dev_blue_target_group_name
  dev_green_target_group_name     = module.load_balancer.dev_green_target_group_name
  prod_listener_arns              = [module.load_balancer.https_listener_arn]
  test_listener_arns              = [module.load_balancer.https_test_listener_arn]
  
  # 자동 롤백 설정
  enable_auto_rollback            = var.enable_auto_rollback
  auto_rollback_events            = var.auto_rollback_events
  
  # 알람 설정
  enable_alarm_configuration      = var.enable_alarm_configuration
  alarm_names                     = var.alarm_names
}
