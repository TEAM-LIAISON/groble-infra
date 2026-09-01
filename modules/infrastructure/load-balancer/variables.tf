# VPC 관련 변수
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

# Security Group 관련 변수
variable "load_balancer_sg_id" {
  description = "ID of the load balancer security group"
  type        = string
}

# 프로젝트 관련 변수
variable "project_name" {
  description = "Name of the project"
  type        = string
}

# Load Balancer 설정 변수
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 300
}

# 헬스체크 관련 변수
#
# ⚠️ prod / dev 를 나눠 둔 이유는 값을 다르게 쓰려는 것이 아니라 **따로 바꿀 수 있게** 하기
#    위해서다. Phase 6 에서 경로를 /actuator/health → /actuator/health/readiness 로 옮기는데,
#    dev 에서 먼저 검증한 뒤 prod 로 간다.
#    변수가 하나이던 시절에는 dev 만 바꾸는 순간 prod 타깃그룹도 함께 바뀌었고, prod 앱에
#    아직 그 엔드포인트가 없으면 60초 뒤 전 태스크가 unhealthy 가 된다
#    (prod TG 는 unhealthy_threshold 2 × interval 30).
#    → docs/runbook/phase-06-deployment-controller.md 의 0단계
variable "prod_health_check_path" {
  description = "Prod 타깃그룹(blue/green)의 ALB 헬스체크 경로"
  type        = string
  default     = "/actuator/health"

  validation {
    condition     = can(regex("^/.*", var.prod_health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "dev_health_check_path" {
  description = "Dev 타깃그룹(blue/green)의 ALB 헬스체크 경로"
  type        = string
  default     = "/actuator/health"

  validation {
    condition     = can(regex("^/.*", var.dev_health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

# API 타깃그룹의 등록 해제 대기(초)
#
# 기본값 300 은 AWS 기본값이며 지금까지의 동작 그대로다 (이전에는 미설정이었다).
# Phase 6 에서 60 으로 내린다 — 결제 승인 상한 30초(Payple 왕복 2회)를 덮는 값이다.
# ⚠️ 내리는 방향이므로 in-flight 보호가 줄어든다. 60MB 업로드(~96초)가 잘리는 것은
#    백엔드와 의도적으로 수용하기로 했다 (근본 해법은 presigned 직행, 별건).
#    → docs/handoff/rolling-deploy-prerequisites.md §4-4 · §5-4
# 경로와 같은 이유로 prod / dev 를 나눠 둔다 — dev 먼저 내리고 검증한 뒤 prod 로 간다.
variable "prod_deregistration_delay" {
  description = "Prod 타깃그룹(blue/green)의 등록 해제 대기(초)"
  type        = number
  default     = 300
}

variable "dev_deregistration_delay" {
  description = "Dev 타깃그룹(blue/green)의 등록 해제 대기(초)"
  type        = number
  default     = 300
}

# SSL 인증서 관련 변수
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  
  validation {
    condition     = can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", var.ssl_certificate_arn)) || var.ssl_certificate_arn == ""
    error_message = "SSL certificate ARN must be a valid ACM certificate ARN or empty string."
  }
}

variable "additional_ssl_certificate_arn" {
  description = "Additional SSL certificate ARN for ALB"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", var.additional_ssl_certificate_arn)) || var.additional_ssl_certificate_arn == ""
    error_message = "Additional SSL certificate ARN must be a valid ACM certificate ARN or empty string."
  }
}

variable "extra_ssl_certificate_arns" {
  description = "Additional SSL certificate ARNs attached to both the 443 and 9443 HTTPS listeners"
  type        = list(string)
  default     = []
}

variable "monitoring_deregistration_delay" {
  description = <<-EOT
    모니터링 타깃그룹의 등록 해제 대기(초).

    모니터링 스택은 host 모드 네트워킹이라 포트가 겹친다 — ECS 가 구 태스크를 먼저
    빼야 하고, 드레이닝이 끝날 때까지 신 태스크를 배치하지 못한다.
    기본값 300초에서는 **이미지를 올릴 때마다 관측이 5분 넘게 끊긴다.**
    2026-08-30 Grafana 배포에서 실제로 약 6분 내려가 있었다.

    사용자 트래픽을 받지 않으므로 길게 드레이닝할 이유가 없다.

    ⚠️ 이 값을 API 타깃그룹에 그대로 옮기지 말 것. 거기서 300초는 낭비가 아니라
       실제 in-flight 드레이닝 시간이다 — 태스크는 DEACTIVATING 동안 살아서
       요청을 처리하고, SIGTERM 은 그 뒤에 온다.
  EOT
  type        = number
  default     = 30
}
