# AWS 기본 설정 변수들
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name for shared resources"
  type        = string
  default     = "shared"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "groble"
}

# VPC 관련 변수들
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# EC2 인스턴스 관련 변수들
variable "key_pair_name" {
  description = "Name of the AWS key pair for EC2 instances"
  type        = string
  default     = ""
}

variable "prod_instance_count" {
  description = "Number of production EC2 instances"
  type        = number
  default     = 1
}

variable "prod_instance_type" {
  description = "Production EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  description = "Monitoring EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "dev_instance_type" {
  description = "Development EC2 instance type"
  type        = string
  default     = "t3.small"
}

# 로드 밸런서 관련 변수들
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for application containers"
  type        = string
  default     = "/actuator/health"
}

# SSH 접근 관련 변수들
variable "trusted_ips" {
  description = "List of trusted IP addresses for direct SSH access to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# SSL 인증서 관련 변수들
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
  default     = ""
}

# CodeDeploy 관련 변수들
variable "prod_deployment_config" {
  description = "CodeDeploy deployment configuration for production"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "dev_deployment_config" {
  description = "CodeDeploy deployment configuration for development"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
}

variable "deployment_ready_timeout_action" {
  description = "Action to take when deployment is ready timeout"
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
}

variable "deployment_ready_wait_time" {
  description = "Time to wait before deployment ready timeout (minutes)"
  type        = number
  default     = 0
}

variable "termination_wait_time" {
  description = "Time to wait before terminating old tasks (minutes)"
  type        = number
  default     = 2
}

variable "enable_auto_rollback" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
}


#################################
# WAF 관련 변수들
#################################

variable "allowed_country_codes" {
  description = "List of allowed country codes for WAF geo-blocking"
  type        = list(string)
  default = [
    "KR", # South Korea
    "JP", # Japan
    "SG", # Singapore
    "AU", # Australia
    "NZ", # New Zealand
    "HK", # Hong Kong
    "TW", # Taiwan
    "TH", # Thailand
    "VN", # Vietnam
    "MY", # Malaysia
    "PH", # Philippines
    "ID", # Indonesia
    "IN"  # India
  ]
}

variable "rate_limit_per_ip" {
  description = "WAF rate limit per IP address (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "rate_limit_global" {
  description = "WAF global rate limit (requests per 5 minutes)"
  type        = number
  default     = 50000
}

variable "rate_limit_login_endpoints" {
  description = "WAF rate limit for login/auth endpoints (requests per 5 minutes)"
  type        = number
  default     = 50
}

variable "max_request_size" {
  description = "Maximum request body size in bytes for WAF (1MB = 1048576)"
  type        = number
  default     = 1048576
}

# --- Phase 1: 알람 백스톱 --------------------------------------------------

variable "slack_workspace_id" {
  description = <<-EOT
    AWS 콘솔에서 Slack 워크스페이스를 승인한 뒤 얻는 ID (T로 시작).
    이 승인은 Terraform으로 할 수 없다 — 콘솔에서 1회 수행한다.
    비어 있으면 SNS 토픽만 만들고 Chatbot은 생성하지 않는다.
  EOT
  type        = string
  default     = ""
}

variable "slack_channel_id_prod" {
  description = "즉시 대응이 필요한 알림을 받을 Slack 채널 ID (C로 시작). 채널 이름이 아니다"
  type        = string
  default     = ""
}

variable "slack_channel_id_dev" {
  description = "업무 시간에 확인하는 알림을 받을 Slack 채널 ID"
  type        = string
  default     = ""
}

#################################
# Phase 3 — NAT Gateway 전환
#################################

variable "nat_gateway_az" {
  description = "NAT Gateway 를 배치할 AZ. 계획서 §2.2 의 '전 구성요소 2c 정렬'을 따른다"
  type        = string
  default     = "ap-northeast-2c"
}

variable "use_nat_gateway" {
  description = <<-EOT
    private 서브넷의 기본 경로(0.0.0.0/0)를 NAT Gateway 로 보낼지 여부.

    false — 모니터링 인스턴스 ENI 경유 (As-Is)
    true  — NAT Gateway 경유 (Phase 3 전환 완료 상태)

    ⚠️ 이 값을 바꾸는 apply 가 곧 Phase 3 의 전환 그 자체다.
       진행 중이던 아웃바운드 연결이 전부 끊기므로 저트래픽·무배포 시간대에만 바꾼다.
       롤백도 이 값을 되돌리는 것이며, 되돌릴 때도 동일하게 연결이 끊긴다.
  EOT
  type        = bool
  default     = false
}

variable "attach_s3_endpoint_to_private_rt" {
  description = <<-EOT
    S3 Gateway Endpoint 를 private route table 에 연결할지 여부.

    use_nat_gateway 와 독립적인 스위치다. 새벽 전환 때 라우트 교체를 먼저 검증하고
    이것을 나중에 켜면, 문제가 생겼을 때 둘 중 무엇이 원인인지 바로 갈린다.

    ⚠️ 켜는 순간 진행 중이던 S3 연결(파일 업로드 · ECR 레이어 pull)이 끊긴다.
  EOT
  type        = bool
  default     = false
}

variable "create_nat_gateway" {
  description = <<-EOT
    NAT Gateway 생성 여부.

    false — EIP 만 만들어 IP 를 확보한다 (시간당 요금 없음)
    true  — NAT Gateway 를 만든다 (약 $0.059/시간). 트래픽 경로는 use_nat_gateway 가 결정한다

    외부 업체 허용목록에 IP 등록이 필요하면, EIP 로 IP 를 먼저 전달해 등록을 마친 뒤 켠다.
  EOT
  type        = bool
  default     = false
}

#################################
# 신 모니터링 노드 (Phase 4)
#################################

variable "create_monitoring_v2_instance" {
  description = <<-EOT
    Phase 4 의 신 모니터링 노드(private 2c, AL2023)를 만들지 여부.

    false — 만들지 않는다 (기본, 현 상태)
    true  — D단계. 구 노드와 병존하며 사용자 영향이 없다.
            스택 이동은 E단계(구 노드 DRAINING)에서 별도로 한다
  EOT
  type        = bool
  default     = false
}

variable "monitoring_v2_instance_type" {
  description = "신 모니터링 노드 타입. 모듈 변수의 메모리 주의사항 참조"
  type        = string
  default     = "t3.small"
}

variable "monitoring_v2_instance_private_ip" {
  description = "신 모니터링 노드의 고정 사설 IP (private 2c). dev 노드 10.0.12.215 와 겹치지 않게 할 것"
  type        = string
  default     = "10.0.12.100"
}
