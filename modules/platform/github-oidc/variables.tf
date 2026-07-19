variable "github_org" {
  description = "GitHub organization/owner (e.g. TEAM-LIAISON)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name that assumes the CI role (e.g. groble-images)"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC"
  type        = string
  default     = "groble-images-ci"
}

# 트러스트 정책의 sub(subject) 허용 패턴.
# null이면 repo:<org>/<repo>:* 로 자동 설정 (모든 브랜치/태그 허용).
# 좁히려면 예: ["repo:TEAM-LIAISON/groble-images:ref:refs/heads/main"]
variable "subject_claims" {
  description = "Allowed GitHub OIDC subject (sub) claims for the trust policy. null = repo:<org>/<repo>:*"
  type        = list(string)
  default     = null
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the CI role is allowed to push/pull"
  type        = list(string)
}

# OIDC provider는 계정당 하나만 존재 가능.
# 이미 있으면 false로 두고 oidc_provider_arn을 넘긴다.
variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if it already exists in the account."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "Existing OIDC provider ARN (used when create_oidc_provider = false)"
  type        = string
  default     = ""
}
