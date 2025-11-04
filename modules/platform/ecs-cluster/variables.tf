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
