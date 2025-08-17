# VPC 출력
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
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

# ECS Cluster 출력
output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

# IAM Roles 출력
output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.iam_roles.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = module.iam_roles.ecs_task_role_arn
}

# Load Balancer 출력
output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.load_balancer.load_balancer_dns_name
}

output "alb_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = module.load_balancer.https_listener_arn
}

output "monitoring_target_group_arn" {
  description = "ARN of the monitoring target group"
  value       = module.load_balancer.monitoring_target_group_arn
}

# Security Groups 출력
output "monitoring_security_group_id" {
  description = "ID of the monitoring security group"
  value       = module.security_groups.monitor_target_group_sg_id
}

# Service Discovery 출력
output "service_discovery_namespace_id" {
  description = "Service Discovery namespace ID"
  value       = module.service_discovery.namespace_id
}

output "service_discovery_namespace_name" {
  description = "Service Discovery namespace name"
  value       = module.service_discovery.namespace_name
}
