provider "aws" {
  region  = var.aws_region
  profile = "groble-terraform"
}

# 기존 shared 리소스 참조
data "terraform_remote_state" "shared" {
  backend = "local"
  config = {
    path = "../shared/terraform.tfstate"
  }
}

# Use existing monitoring target group from shared environment


# Loki Service
module "loki" {
  source = "../../modules/services/monitoring/loki"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  loki_image                           = var.loki_image
  loki_version                         = var.loki_version
  log_retention_days                   = var.loki_log_retention_days
  cpu                                  = var.loki_cpu
  memory                               = var.loki_memory
  container_memory                     = var.loki_container_memory
  container_memory_reservation         = var.loki_container_memory_reservation
  desired_count                        = var.desired_count
  
  aws_region                           = var.aws_region
}

# OpenTelemetry Collector Service
module "otelcol" {
  source = "../../modules/services/monitoring/otelcol"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  otelcol_image   = var.otelcol_image
  otelcol_version = var.otelcol_version
  
  # Resource configuration
  cpu                                  = var.otelcol_cpu
  memory                               = var.otelcol_memory
  container_memory                     = var.otelcol_container_memory
  container_memory_reservation         = var.otelcol_container_memory_reservation
  desired_count                        = var.desired_count


  aws_region                          = var.aws_region

  # No dependencies needed with localhost
}

# Grafana Service
module "grafana" {
  source = "../../modules/services/monitoring/grafana"

  environment            = "monitoring"
  ecs_cluster_id        = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  target_group_arn      = data.terraform_remote_state.shared.outputs.monitoring_target_group_arn
  alb_listener          = null
  execution_role_arn    = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn         = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  grafana_image         = var.grafana_image
  grafana_version       = var.grafana_version
  grafana_domain        = var.grafana_domain
  grafana_plugins       = var.grafana_plugins
  admin_password        = var.grafana_admin_password
  
  # Grafana 리소스 설정
  cpu                         = var.grafana_cpu
  memory                      = var.grafana_memory
  container_memory           = var.grafana_container_memory
  container_memory_reservation = var.grafana_container_memory_reservation
  desired_count              = var.grafana_desired_count
  
  aws_region            = var.aws_region

  # No dependencies needed with localhost
}

# Prometheus Service
module "prometheus" {
  source = "../../modules/services/monitoring/prometheus"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  prometheus_image                = var.prometheus_image
  prometheus_version              = var.prometheus_version
  prometheus_domain               = var.prometheus_domain
  target_group_arn                = var.prometheus_target_group_arn
  alb_listener                    = null

  # Resource configuration
  cpu                            = var.prometheus_cpu
  memory                         = var.prometheus_memory
  container_memory               = var.prometheus_container_memory
  container_memory_reservation   = var.prometheus_container_memory_reservation
  desired_count                  = var.desired_count

  # Storage configuration
  metrics_retention_days         = var.prometheus_metrics_retention_days
  local_retention_time           = var.prometheus_local_retention_time
  local_retention_size           = var.prometheus_local_retention_size

  # Prometheus settings
  scrape_interval                = var.prometheus_scrape_interval
  evaluation_interval            = var.prometheus_evaluation_interval
  log_level                      = var.prometheus_log_level

  # Integration endpoints - using localhost
  otelcol_endpoint               = "localhost:8888"

  aws_region                     = var.aws_region

  # No dependencies needed with localhost
}

# Node Exporter Service (DAEMON - runs on all instances)
module "node_exporter" {
  source = "../../modules/services/monitoring/node-exporter"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn
}

# cAdvisor Service (DAEMON - runs on all instances)
module "cadvisor" {
  source = "../../modules/services/monitoring/cadvisor"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn
}

# RDS Exporter Service (single instance on monitoring)
module "rds_exporter" {
  source = "../../modules/services/monitoring/rds-exporter"
  count  = var.rds_endpoint != "" ? 1 : 0

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  rds_endpoint       = var.rds_endpoint
  database_username  = var.rds_database_username
  database_password  = var.rds_database_password
}
