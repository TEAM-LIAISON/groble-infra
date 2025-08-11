#################################
# Shared Outputs for Groble Infrastructure
#################################
# 
# 이 파일은 모든 환경에서 공통으로 사용되는 출력값들을 정의합니다.
# 각 환경에서 필요에 따라 이 출력들을 참조할 수 있습니다.

#################################
# 네트워크 관련 출력
#################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "availability_zones" {
  description = "Availability zones used"
  value       = module.vpc.availability_zones
}

#################################
# 보안 그룹 관련 출력
#################################

output "load_balancer_sg_id" {
  description = "Security group ID for load balancer"
  value       = module.security_groups.load_balancer_sg_id
}

output "api_task_sg_id" {
  description = "Security group ID for API tasks"
  value       = module.security_groups.api_task_sg_id
}

output "prod_target_group_sg_id" {
  description = "Security group ID for production target group"
  value       = module.security_groups.prod_target_group_sg_id
}

output "dev_target_group_sg_id" {
  description = "Security group ID for development target group"
  value       = module.security_groups.develop_target_group_sg_id
}

output "monitoring_target_group_sg_id" {
  description = "Security group ID for monitoring target group"
  value       = module.security_groups.monitor_target_group_sg_id
}

#################################
# 로드 밸런서 관련 출력
#################################

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = module.load_balancer.load_balancer_arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.load_balancer.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.load_balancer.load_balancer_zone_id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = module.load_balancer.https_listener_arn
}

#################################
# IAM 관련 출력
#################################

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.iam_roles.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = module.iam_roles.ecs_task_role_arn
}

output "ecs_instance_profile_name" {
  description = "Name of the ECS instance profile"
  value       = module.iam_roles.ecs_instance_profile_name
}

output "codedeploy_service_role_arn" {
  description = "ARN of the CodeDeploy service role"
  value       = module.iam_roles.codedeploy_service_role_arn
}

#################################
# ECS 클러스터 관련 출력
#################################

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.cluster_arn
}

#################################
# 환경별 조건부 출력
#################################

# Production 인스턴스 관련 출력 (Production 환경에서만 사용)
output "prod_instance_ids" {
  description = "IDs of production instances"
  value       = try(module.ecs_cluster.prod_instance_ids, [])
}

output "prod_instance_private_ips" {
  description = "Private IP addresses of production instances"
  value       = try(module.ecs_cluster.prod_instance_private_ips, [])
}

output "prod_instance_public_ips" {
  description = "Public IP addresses of production instances"
  value       = try(module.ecs_cluster.prod_instance_public_ips, [])
}

# Development 인스턴스 관련 출력 (Development 환경에서만 사용)
output "dev_instance_id" {
  description = "ID of development instance"
  value       = try(module.ecs_cluster.dev_instance_id, "")
}

output "dev_instance_private_ip" {
  description = "Private IP address of development instance"
  value       = try(module.ecs_cluster.dev_instance_private_ip, "")
}

output "dev_instance_public_ip" {
  description = "Public IP address of development instance"
  value       = try(module.ecs_cluster.dev_instance_public_ip, "")
}

# Monitoring 인스턴스 관련 출력 (모든 환경에서 사용)
output "monitoring_instance_id" {
  description = "ID of monitoring instance"
  value       = module.ecs_cluster.monitoring_instance_id
}

output "monitoring_instance_private_ip" {
  description = "Private IP address of monitoring instance"
  value       = module.ecs_cluster.monitoring_instance_private_ip
}

output "monitoring_instance_public_ip" {
  description = "Public IP address of monitoring instance"
  value       = module.ecs_cluster.monitoring_instance_public_ip
}

#################################
# ECR 관련 출력
#################################

# Production ECR 출력 (Production 환경에서만 사용)
output "prod_ecr_repository_url" {
  description = "URL of the production ECR repository"
  value       = try(module.ecr.prod_repository_url, "")
}

output "prod_ecr_repository_arn" {
  description = "ARN of the production ECR repository"
  value       = try(module.ecr.prod_repository_arn, "")
}

# Development ECR 출력 (Development 환경에서만 사용)
output "dev_ecr_repository_url" {
  description = "URL of the development ECR repository"
  value       = try(module.ecr.dev_repository_url, "")
}

output "dev_ecr_repository_arn" {
  description = "ARN of the development ECR repository"
  value       = try(module.ecr.dev_repository_arn, "")
}

#################################
# Route53 관련 출력
#################################

output "route53_zone_id" {
  description = "Zone ID of the Route53 hosted zone"
  value       = try(module.route53.zone_id, "")
}

output "route53_name_servers" {
  description = "Name servers of the Route53 hosted zone"
  value       = try(module.route53.name_servers, [])
}

#################################
# CodeDeploy 관련 출력
#################################

output "codedeploy_application_name" {
  description = "Name of the CodeDeploy application"
  value       = module.codedeploy.application_name
}

output "artifacts_bucket_name" {
  description = "Name of the artifacts S3 bucket"
  value       = try(module.codedeploy.artifacts_bucket_name, "")
}

# Production CodeDeploy 출력 (Production 환경에서만 사용)
output "prod_deployment_group_name" {
  description = "Name of the production deployment group"
  value       = try(module.codedeploy.prod_deployment_group_name, "")
}

# Development CodeDeploy 출력 (Development 환경에서만 사용)
output "dev_deployment_group_name" {
  description = "Name of the development deployment group"
  value       = try(module.codedeploy.dev_deployment_group_name, "")
}

#################################
# 서비스 관련 출력
#################################

output "api_service_name" {
  description = "Name of the API service"
  value       = try(module.api_service.service_name, "")
}

output "mysql_service_name" {
  description = "Name of the MySQL service"
  value       = try(module.mysql_service.service_name, "")
}

output "redis_service_name" {
  description = "Name of the Redis service"
  value       = try(module.redis_service.service_name, "")
}

#################################
# 환경 정보 출력
#################################

output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
