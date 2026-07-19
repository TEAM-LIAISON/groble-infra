output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions (role-to-assume in the workflow)"
  value       = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = local.provider_arn
}
