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
