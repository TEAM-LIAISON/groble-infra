variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment (e.g., prod, dev)"
  type        = string
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