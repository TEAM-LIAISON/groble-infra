variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

# 같은 노드에 exporter 를 여러 개 띄우기 위한 두 변수
#
# Prometheus 의 rds-exporter job 이 `localhost:9104` 를 긁는다(groble-images
# prometheus.yml). 스크레이프가 로컬 고정이라 **exporter 는 Prometheus 와 같은
# 모니터링 노드에 있어야 한다** — 대상 RDS 가 dev 든 prod 든 마찬가지다.
# 그래서 인스턴스를 늘리려면 노드를 나누는 게 아니라 포트와 이름을 나눠야 한다.
#
# ⚠️ 기본값은 기존 prod exporter 를 그대로 재현한다. 바꾸면 태스크 정의 family 가
#    달라져 새 리소스로 잡히므로, 기존 호출부는 이 둘을 넘기지 않는다.
variable "name_suffix" {
  description = <<-EOT
    task definition family · ECS 서비스 이름에 붙는 접미사.

    이름이 `<environment>-rds-exporter<name_suffix>` 로 만들어지는데,
    호출부가 둘 다 environment = "monitoring" 을 넘기므로(exporter 가 도는 곳이
    모니터링 노드라서) 접미사 없이는 dev·prod 인스턴스의 이름이 충돌한다.
  EOT
  type        = string
  default     = ""
}

variable "exporter_port" {
  description = <<-EOT
    exporter 가 listen 하는 host 포트. host 네트워킹이라 노드에서 유일해야 한다.

    이 값을 바꾸면 groble-images 의 prometheus.yml 에 같은 포트를 보는 job 을
    추가해야 한다. 넣지 않으면 **경고 없이 스크레이프되지 않는다.**
  EOT
  type        = number
  default     = 9104
}

variable "rds_exporter_image" {
  description = "RDS Exporter Docker image (MySQL exporter compatible)"
  type        = string
  default     = "prom/mysqld-exporter"
}

variable "rds_exporter_version" {
  description = "RDS Exporter version"
  type        = string
  default     = "v0.15.1"
}

variable "rds_endpoint" {
  description = "RDS endpoint address (without port)"
  type        = string
}

variable "database_username" {
  description = "RDS database username"
  type        = string
  sensitive   = true
}

variable "database_password" {
  description = "RDS database password"
  type        = string
  sensitive   = true
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 128
}

variable "memory" {
  description = "Task memory in MB"
  type        = number
  default     = 128
}

variable "container_memory" {
  description = "Container memory limit in MB"
  type        = number
  default     = 128
}

variable "container_memory_reservation" {
  description = "Container memory reservation in MB"
  type        = number
  default     = 64
}
