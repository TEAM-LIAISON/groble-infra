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
variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
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
