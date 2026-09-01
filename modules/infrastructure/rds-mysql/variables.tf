variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment (e.g., prod, dev)"
  type        = string
}

variable "db_subnet_group_name" {
  description = <<-EOT
    DB 서브넷 그룹 이름. null 이면 "<project_name>-mysql-subnet-group" 로 떨어진다.

    ⚠️ 파라미터 그룹은 이름에 environment 가 들어가는데 **서브넷 그룹만 빠져 있었다.**
    그대로 두면 두 번째 환경(dev)이 같은 이름을 만들려다 DBSubnetGroupAlreadyExists 로 죽는다.

    기본값을 바꾸지 않는 이유: 이름은 force-new 속성이라 prod 쪽 이름을 건드리면
    서브넷 그룹 replace 가 걸리고 붙어 있는 RDS 수정까지 딸려 온다.
    **prod 는 null 을 유지하고, 신규 환경만 명시적으로 다른 이름을 넘긴다.**
  EOT
  type        = string
  default     = null
}

variable "create_legacy_80_parameter_group" {
  description = <<-EOT
    mysql8.0 파라미터 그룹을 만들지 여부.

    prod 가 8.0 → 8.4 로 올라가며 mysql_params_84 로 갈아탄 뒤 이 그룹은 아무도 참조하지
    않는 잔재가 되었다. state 에 남아 있어 prod 는 true 로 둔다(제거는 Phase 12).
    **신규 환경은 false** — 쓰지도 않을 그룹을 새로 만들 이유가 없다.
  EOT
  type        = bool
  default     = true
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS MySQL instance"
  type        = string
}

variable "instance_class" {
  description = "The RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "database_name" {
  description = "The name of the database to create"
  type        = string
}

variable "database_username" {
  description = "Username for the master DB user"
  type        = string
  default     = "groble_root"
}

variable "database_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

variable "allocated_storage" {
  description = "The allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "The upper limit for automatic storage scaling in GB"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "The daily time range during which backups are created"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "The weekly time range during which maintenance can occur"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "The AZ for the RDS instance (if multi_az is false)"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying"
  type        = bool
  default     = false
}