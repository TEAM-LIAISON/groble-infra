output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.cluster.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.cluster.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.cluster.arn
}

# CloudWatch Log Groups
output "prod_log_group_name" {
  description = "Production log group name"
  value       = var.create_prod_logs ? aws_cloudwatch_log_group.prod_logs[0].name : null
}

output "dev_log_group_name" {
  description = "Development log group name"
  value       = var.create_dev_logs ? aws_cloudwatch_log_group.dev_logs[0].name : null
}

# Instance IDs
output "prod_instance_ids" {
  description = "Production instance IDs"
  value       = aws_instance.prod_instance[*].id
}

output "monitoring_instance_id" {
  description = "Monitoring instance ID"
  value       = var.create_monitoring_instance ? aws_instance.monitoring_instance[0].id : null
}

output "dev_instance_id" {
  description = "Development instance ID"
  value       = var.create_dev_instance ? aws_instance.dev_instance[0].id : null
}

# Instance Public IPs
output "prod_instance_public_ips" {
  description = "Production instance public IPs"
  value       = aws_instance.prod_instance[*].public_ip
}

output "monitoring_instance_public_ip" {
  description = "Monitoring instance public IP"
  value       = var.create_monitoring_instance ? aws_instance.monitoring_instance[0].public_ip : null
}

output "dev_instance_public_ip" {
  description = "Development instance public IP"
  value       = var.create_dev_instance ? aws_instance.dev_instance[0].public_ip : null
}

# Instance Private IPs
output "prod_instance_private_ips" {
  description = "Production instance private IPs"
  value       = aws_instance.prod_instance[*].private_ip
}

output "monitoring_instance_private_ip" {
  description = "Monitoring instance private IP"
  value       = var.create_monitoring_instance ? aws_instance.monitoring_instance[0].private_ip : null
}

output "dev_instance_private_ip" {
  description = "Development instance private IP"
  value       = var.create_dev_instance ? aws_instance.dev_instance[0].private_ip : null
}
