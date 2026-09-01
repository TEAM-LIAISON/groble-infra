variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "grafana_image" {
  description = "Grafana Docker image"
  type        = string
  default     = "grafana/grafana"
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "latest"
}

variable "grafana_domain" {
  description = "Grafana domain name"
  type        = string
}

variable "grafana_plugins" {
  description = "Grafana plugins to install"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_cpu" {
  description = "CPU units for the Grafana task (250 = 0.25 vCPU)"
  type        = number
  default     = 250
}

variable "grafana_memory" {
  description = "Memory for the Grafana task (MB)"
  type        = number
  default     = 256
}

variable "grafana_container_memory" {
  description = "Hard memory limit for Grafana container (MB)"
  type        = number
  default     = 256
}

variable "grafana_container_memory_reservation" {
  description = "Soft memory limit for Grafana container (MB)"
  type        = number
  default     = 128
}

variable "grafana_desired_count" {
  description = "Desired number of Grafana tasks"
  type        = number
  default     = 1
}

# Loki 관련 변수
# config baking: groble-images CI가 push한 full image ref(repo:tag) 하나만 받음.
variable "monitoring_loki_image" {
  description = "loki baked-config image (repo:tag) from groble-images CI"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.monitoring_loki_image))
    error_message = "monitoring_loki_image must be a valid Docker image ref (repo:tag)."
  }
}

variable "loki_log_retention_days" {
  description = <<-EOT
    Loki S3 버킷의 lifecycle 만료 일수.

    이것은 "로그 조회 가능 기간"이 아니다. 조회 기간을 결정하는 건 Loki
    compactor의 retention_period(현재 180d, groble-images에 baked)이고,
    이 lifecycle은 Loki가 지우지 못한 고아 객체를 치우는 백스톱이다.

    불변조건: Loki retention_period < 이 값.
    역전되면 S3가 청크를 먼저 지우는데 Loki 인덱스는 그걸 모르기 때문에,
    만료 구간을 조회할 때 청크 누락으로 쿼리가 깨진다.
  EOT
  type        = number
  default     = 210 # = Loki retention 180d + 마진 30일
}

variable "loki_cpu" {
  description = "CPU units for Loki task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "loki_memory" {
  description = "Memory for Loki task (MB)"
  type        = number
  default     = 512
}

variable "loki_container_memory" {
  description = "Hard memory limit for Loki container (MB)"
  type        = number
  default     = 512
}

variable "loki_container_memory_reservation" {
  description = "Soft memory limit for Loki container (MB)"
  type        = number
  default     = 256
}

# OpenTelemetry Collector 관련 변수
# config baking: groble-images CI가 push한 full image ref(repo:tag) 하나만 받음.
variable "monitoring_otelcol_image" {
  description = "otelcol baked-config image (repo:tag) from groble-images CI"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.monitoring_otelcol_image))
    error_message = "monitoring_otelcol_image must be a valid Docker image ref (repo:tag)."
  }
}

variable "otelcol_cpu" {
  description = "CPU units for OpenTelemetry Collector task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "otelcol_memory" {
  description = "Memory for OpenTelemetry Collector task (MB)"
  type        = number
  default     = 256
}

variable "otelcol_container_memory" {
  description = "Hard memory limit for OpenTelemetry Collector container (MB)"
  type        = number
  default     = 256
}

variable "otelcol_container_memory_reservation" {
  description = "Soft memory limit for OpenTelemetry Collector container (MB)"
  type        = number
  default     = 128
}

# Prometheus 관련 변수
# config baking: groble-images CI가 push한 full image ref(repo:tag) 하나만 받음.
variable "monitoring_prometheus_image" {
  description = "prometheus baked-config image (repo:tag) from groble-images CI"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.monitoring_prometheus_image))
    error_message = "monitoring_prometheus_image must be a valid Docker image ref (repo:tag)."
  }
}

variable "prometheus_domain" {
  description = "Prometheus domain name"
  type        = string
  default     = "prometheus.example.com"
}

variable "prometheus_target_group_arn" {
  description = "ALB target group ARN for Prometheus (optional)"
  type        = string
  default     = ""
}

variable "prometheus_cpu" {
  description = "CPU units for Prometheus task (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "prometheus_memory" {
  description = "Memory for Prometheus task (MB)"
  type        = number
  default     = 1024
}

variable "prometheus_container_memory" {
  description = "Hard memory limit for Prometheus container (MB)"
  type        = number
  default     = 1024
}

variable "prometheus_container_memory_reservation" {
  description = "Soft memory limit for Prometheus container (MB)"
  type        = number
  default     = 768
}

variable "prometheus_metrics_retention_days" {
  description = "S3 metrics retention period in days"
  type        = number
  default     = 90
}

variable "prometheus_local_retention_time" {
  description = "Local TSDB retention time"
  type        = string
  default     = "15d"
}

variable "prometheus_local_retention_size" {
  description = "Local TSDB retention size"
  type        = string
  default     = "10GB"
}

variable "prometheus_scrape_interval" {
  description = "Global scrape interval"
  type        = string
  default     = "15s"
}

variable "prometheus_evaluation_interval" {
  description = "Rule evaluation interval"
  type        = string
  default     = "30s"
}

variable "prometheus_log_level" {
  description = "Prometheus log level"
  type        = string
  default     = "info"
}

# Common service configuration
variable "desired_count" {
  description = "Desired number of tasks for services (except Grafana which has its own variable)"
  type        = number
  default     = 1
}

# RDS Exporter configuration
variable "rds_endpoint" {
  description = "RDS endpoint address for monitoring"
  type        = string
  default     = ""
}

variable "rds_database_username" {
  description = "RDS database username for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rds_database_password" {
  description = "RDS database password for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

# Dev RDS exporter
#
# Phase 5 로 dev DB 가 컨테이너 MySQL 에서 RDS 로 옮겨가면서 감시 대상이 하나 늘었다.
# exporter 는 **prod 와 같은 모니터링 노드**에 뜬다 — Prometheus 의 rds-exporter job 이
# localhost 를 긁기 때문이다(groble-images prometheus.yml). 따라서 두 exporter 를
# 가르는 것은 노드가 아니라 포트(9104 / 9105)와 이름 접미사다.
#
# 네트워크 경로는 이미 열려 있다 — groble-rds-mysql-dev-sg 의 3306 이
# groble-monitor-target-group 을 SG 참조로 허용한다 (Phase 5 에서 만들었다).
variable "rds_dev_endpoint" {
  description = "Dev RDS endpoint address. 비우면 dev exporter 를 만들지 않는다"
  type        = string
  default     = ""
}

variable "rds_dev_database_username" {
  description = "Dev RDS database username for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rds_dev_database_password" {
  description = "Dev RDS database password for exporter"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rds_dev_exporter_port" {
  description = <<-EOT
    dev exporter 의 host 포트. prod 가 9104 를 쓰므로 겹치면 안 된다.

    ⚠️ 이 값을 바꾸면 groble-images 의 prometheus.yml 에 같은 포트를 보는
    rds-exporter-dev job 도 함께 고쳐야 한다. 안 하면 조용히 스크레이프되지 않는다.
  EOT
  type        = number
  default     = 9105
}


#################################
# Exporter 자원 (Phase 4 재배분으로 노출)
#################################
# 이 셋은 이전까지 모듈 기본값을 그대로 썼다. 실측 결과 크게 과대 선언되어 있어
# 값을 여기로 끌어올려 조정 가능하게 한다.
#
# ⚠️ node-exporter 와 cadvisor 는 DAEMON 이다 — prod·dev 노드에도 함께 적용된다.

variable "node_exporter_memory" {
  description = "node-exporter task memory (MB). 7일 최대 실측 18MB"
  type        = number
  default     = 48
}

variable "node_exporter_container_memory_reservation" {
  description = "node-exporter soft limit (MB)"
  type        = number
  default     = 32
}

variable "cadvisor_memory" {
  description = "cAdvisor task memory (MB). 7일 최대 실측 34MB"
  type        = number
  default     = 96
}

variable "cadvisor_container_memory_reservation" {
  description = "cAdvisor soft limit (MB)"
  type        = number
  default     = 64
}

variable "rds_exporter_memory" {
  description = "rds-exporter task memory (MB). 7일 최대 실측 15MB"
  type        = number
  default     = 48
}

variable "rds_exporter_container_memory_reservation" {
  description = "rds-exporter soft limit (MB)"
  type        = number
  default     = 32
}
