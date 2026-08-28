# VPC 관련 변수들
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "nat_gateway_az" {
  description = "NAT Gateway 를 배치할 AZ. availability_zones 안의 값이어야 한다"
  type        = string
  default     = "ap-northeast-2c"
}

variable "attach_s3_endpoint_to_private_rt" {
  description = <<-EOT
    S3 Gateway Endpoint 를 private route table 에 연결할지 여부 (Phase 3).

    false — 엔드포인트만 존재하고 트래픽 경로는 그대로 (생성 단계)
    true  — S3 트래픽이 NAT 을 우회해 엔드포인트로 나간다 (전환 단계)

    ⚠️ false → true 로 바꾸는 apply 는 진행 중이던 S3 연결을 끊는다.
  EOT
  type        = bool
  default     = false
}

variable "create_nat_gateway" {
  description = <<-EOT
    NAT Gateway 를 생성할지 여부 (Phase 3).

    false — EIP 만 만든다. 등록할 IP 를 먼저 확보하는 단계이며, 시간당 요금이 없다
    true  — NAT Gateway 를 만든다. 만들어도 use_nat_gateway 가 false 면 트래픽은 그대로다

    외부 업체 허용목록 등록이 필요한 경우, EIP 로 IP 를 먼저 받아 등록을 진행하고
    등록이 끝난 뒤 이 값을 켠다.
  EOT
  type        = bool
  default     = false
}
