# Production Repository Outputs
output "prod_repository_arn" {
  description = "Production ECR repository ARN"
  value       = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].arn : null
}

output "prod_repository_name" {
  description = "Production ECR repository name"
  value       = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].name : null
}

output "prod_repository_url" {
  description = "Production ECR repository URL"
  value       = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].repository_url : null
}

output "prod_registry_id" {
  description = "Production ECR registry ID"
  value       = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].registry_id : null
}

# Development Repository Outputs
output "dev_repository_arn" {
  description = "Development ECR repository ARN"
  value       = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].arn : null
}

output "dev_repository_name" {
  description = "Development ECR repository name"
  value       = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].name : null
}

output "dev_repository_url" {
  description = "Development ECR repository URL"
  value       = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].repository_url : null
}

output "dev_registry_id" {
  description = "Development ECR registry ID"
  value       = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].registry_id : null
}

# Combined Outputs for convenience
output "repository_urls" {
  description = "Map of all repository URLs"
  value = {
    production  = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].repository_url : null
    development = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].repository_url : null
  }
}

output "repository_names" {
  description = "Map of all repository names"
  value = {
    production  = var.create_prod_repository ? aws_ecr_repository.prod_spring_api[0].name : null
    development = var.create_dev_repository ? aws_ecr_repository.dev_spring_api[0].name : null
  }
}
