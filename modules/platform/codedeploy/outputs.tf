# CodeDeploy Application
output "application_id" {
  description = "CodeDeploy application ID"
  value       = aws_codedeploy_app.app.id
}

output "application_name" {
  description = "CodeDeploy application name"
  value       = aws_codedeploy_app.app.name
}

output "application_arn" {
  description = "CodeDeploy application ARN"
  value       = aws_codedeploy_app.app.arn
}

# Production Deployment Group
output "prod_deployment_group_id" {
  description = "Production deployment group ID"
  value       = var.create_prod_deployment_group ? aws_codedeploy_deployment_group.prod_deployment_group[0].id : null
}

output "prod_deployment_group_name" {
  description = "Production deployment group name"
  value       = var.create_prod_deployment_group ? aws_codedeploy_deployment_group.prod_deployment_group[0].deployment_group_name : null
}

# Development Deployment Group
output "dev_deployment_group_id" {
  description = "Development deployment group ID"
  value       = var.create_dev_deployment_group ? aws_codedeploy_deployment_group.dev_deployment_group[0].id : null
}

output "dev_deployment_group_name" {
  description = "Development deployment group name"
  value       = var.create_dev_deployment_group ? aws_codedeploy_deployment_group.dev_deployment_group[0].deployment_group_name : null
}

# S3 Artifacts Bucket
output "artifacts_bucket_id" {
  description = "CodeDeploy artifacts S3 bucket ID"
  value       = var.create_artifacts_bucket ? aws_s3_bucket.codedeploy_artifacts[0].id : null
}

output "artifacts_bucket_name" {
  description = "CodeDeploy artifacts S3 bucket name"
  value       = var.create_artifacts_bucket ? aws_s3_bucket.codedeploy_artifacts[0].bucket : null
}

output "artifacts_bucket_arn" {
  description = "CodeDeploy artifacts S3 bucket ARN"
  value       = var.create_artifacts_bucket ? aws_s3_bucket.codedeploy_artifacts[0].arn : null
}

output "artifacts_bucket_domain_name" {
  description = "CodeDeploy artifacts S3 bucket domain name"
  value       = var.create_artifacts_bucket ? aws_s3_bucket.codedeploy_artifacts[0].bucket_domain_name : null
}

# Combined outputs for convenience
output "deployment_groups" {
  description = "Map of deployment group information"
  value = {
    production = var.create_prod_deployment_group ? {
      id   = aws_codedeploy_deployment_group.prod_deployment_group[0].id
      name = aws_codedeploy_deployment_group.prod_deployment_group[0].deployment_group_name
    } : null
    development = var.create_dev_deployment_group ? {
      id   = aws_codedeploy_deployment_group.dev_deployment_group[0].id
      name = aws_codedeploy_deployment_group.dev_deployment_group[0].deployment_group_name
    } : null
  }
}
