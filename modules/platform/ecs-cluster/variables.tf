variable "project_name" {
  description = "Project name"
  type        = string
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = false
}

# CloudWatch Logs 관련 변수
variable "create_prod_logs" {
  description = "Create production log group"
  type        = bool
  default     = false
}

variable "create_dev_logs" {
  description = "Create development log group"
  type        = bool
  default     = false
}

variable "prod_log_retention_days" {
  description = "Production log retention in days"
  type        = number
  default     = 7
}

variable "dev_log_retention_days" {
  description = "Development log retention in days"
  type        = number
  default     = 3
}

# Instance 생성 여부
variable "create_prod_instance" {
  description = "Create production instances"
  type        = bool
  default     = true
}

variable "create_monitoring_instance" {
  description = "Create monitoring instance"
  type        = bool
  default     = true
}

variable "create_dev_instance" {
  description = "Create development instance"
  type        = bool
  default     = true
}

# Instance 설정
variable "prod_instance_count" {
  description = "Number of production instances"
  type        = number
  default     = 1
}

variable "prod_instance_type" {
  description = "Production instance type"
  type        = string
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  description = "Monitoring instance type"
  type        = string
  default     = "t3.small"
}

variable "dev_instance_type" {
  description = "Development instance type"
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name"
  type        = string
  default     = ""
}

# VPC 및 네트워크 관련
variable "ubuntu_ami_id" {
  description = "Ubuntu AMI ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

# Security Groups
variable "prod_security_group_id" {
  description = "Production security group ID"
  type        = string
}

variable "monitoring_security_group_id" {
  description = "Monitoring security group ID"
  type        = string
}

variable "dev_security_group_id" {
  description = "Development security group ID"
  type        = string
}

# IAM
variable "ecs_instance_profile_name" {
  description = "ECS instance profile name"
  type        = string
}

# Load Balancer
variable "monitoring_target_group_arn" {
  description = "Monitoring target group ARN"
  type        = string
  default     = ""
}

# Route Tables
variable "private_route_table_id" {
  description = "Private route table ID for NAT instance route"
  type        = string
  default     = ""
}

# EBS Volume settings
variable "monitoring_root_volume_size" {
  description = "Root volume size for monitoring instance in GB"
  type        = number
  default     = 30
}

variable "monitoring_root_volume_type" {
  description = "Root volume type for monitoring instance"
  type        = string
  default     = "gp3"
}

# Private IP addresses
variable "prod_instance_private_ip" {
  description = "Static private IP address for production instance"
  type        = string
  default     = "10.0.11.62"
}

variable "dev_instance_private_ip" {
  description = "Static private IP address for development instance"
  type        = string
  default     = "10.0.12.215"
}

variable "monitoring_instance_private_ip" {
  description = "Static private IP address for monitoring instance"
  type        = string
  default     = "10.0.1.193"
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID. use_nat_gateway = true 일 때 기본 경로의 타깃이 된다"
  type        = string
  default     = ""
}

variable "use_nat_gateway" {
  description = <<-EOT
    private 서브넷의 기본 경로를 NAT Gateway 로 보낼지 여부 (Phase 3).

    false — 모니터링 인스턴스 ENI 경유 (As-Is)
    true  — NAT Gateway 경유

    ⚠️ 이 값을 바꾸는 apply 는 진행 중이던 모든 아웃바운드 연결을 끊는다.
       저트래픽·무배포 시간대에만 바꿀 것.
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

    false — 만들지 않는다 (기본)
    true  — 만든다. 구 노드와 병존하며, 이것만으로는 스택이 옮겨가지 않는다
            (E단계에서 구 노드를 DRAINING 으로 바꿔 밀어낸다)
  EOT
  type        = bool
  default     = false
}

variable "monitoring_v2_instance_private_ip" {
  description = <<-EOT
    신 모니터링 노드의 고정 사설 IP. private 2c(10.0.12.0/24) 대역이어야 한다.

    ⚠️ dev 노드(10.0.12.215)와 겹치지 않게 할 것. AWS 가 서브넷당 처음 4개와
       마지막 1개를 예약하므로 10.0.12.4 이상을 쓴다.
  EOT
  type        = string
  default     = "10.0.12.100"
}

variable "monitoring_v2_instance_type" {
  description = <<-EOT
    신 모니터링 노드 타입. 계획서 §0 에 따라 pet 으로 유지한다(ASG 아님).

    2026-08-30 재배분으로 관측 스택 선언 합계가 1,792 → 1,408 MiB 가 되었고,
    ECS_RESERVED_MEMORY 256 기준 여유가 310 MiB 다. small 로 충분하다.
    (재배분 전에는 여유가 54 MiB 뿐이라 t3.medium 상향을 검토했었다)

    기본값이 t3a.small 인 이유 — t3.small 대비 10% 저렴하다
    (ap-northeast-2 온디맨드 $0.0234 vs $0.0260/h, 월 $17.08 vs $18.98).
    vCPU·메모리는 동일하다.

    ⚠️ **t3a.small 은 최대 ENI 가 2개다** (t3.small 은 3개). t3a 계열 중 small 만
       그렇다 — medium 이상은 t3 와 같은 3개다.
       **이 노드에는 무해하다**: 모니터링 서비스 7개가 전부 host 모드라 ENI 를
       소비하지 않는다. 다만 이 노드에 awsvpc 태스크를 올리려 한다면 1개가 상한이다.
  EOT
  type        = string
  default     = "t3a.small"
}
