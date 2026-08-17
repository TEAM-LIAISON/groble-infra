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

output "rds_mysql_security_group_id" {
  description = "ID of the RDS MySQL security group"
  value       = module.security_groups.rds_mysql_sg_id
}

# WAF 출력
output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = module.waf.web_acl_arn
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = module.waf.web_acl_id
}


# --- Phase 1: 알람 백스톱 --------------------------------------------------

output "alerts_sns_topic_arn_prod" {
  description = "즉시 대응 채널의 SNS 토픽 ARN (prod 환경의 알람이 참조한다)"
  value       = module.alerting_prod.sns_topic_arn
}

output "alerts_sns_topic_arn_dev" {
  description = "업무 시간 확인 채널의 SNS 토픽 ARN (dev 환경의 알람이 참조한다)"
  value       = module.alerting_dev.sns_topic_arn
}

output "alerts_slack_enabled" {
  description = "Slack Chatbot 연동이 활성화되었는지 (채널별)"
  value = {
    prod = module.alerting_prod.chatbot_enabled
    dev  = module.alerting_dev.chatbot_enabled
  }
}

output "alb_alarm_names" {
  description = "ALB 관련 알람 이름 목록"
  value       = module.alb_alarms.alarm_names
}
