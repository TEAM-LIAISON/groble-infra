# 도메인 관련 변수
variable "domain_name" {
  description = "Domain name for Route53 records"
  type        = string
  default     = "groble.im"
}

# Load Balancer 관련 변수
variable "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  type        = string
}

variable "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  type        = string
}

# 내부 DNS 관련 변수 (Phase 4)
variable "vpc_id" {
  description = "private hosted zone 을 연결할 VPC"
  type        = string
}

variable "otel_target_private_ip" {
  description = <<-EOT
    otel.internal.<domain> 이 가리킬 사설 IP (Phase 4).

    B 단계 — 구 모니터링 노드 IP (동작 변화 없이 간접화만 도입)
    F 단계 — 신 모니터링 노드 IP 로 바꾸면 60초 내 전환된다 (앱 재배포 없음)
  EOT
  type        = string
}
