provider "aws" {
  region  = var.aws_region
  profile = "groble-terraform"
}

# 기존 shared 리소스 참조
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket  = "groble-terraform-state"
    key     = "environments/shared/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "groble-terraform"
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

  loki_image                   = var.monitoring_loki_image
  log_retention_days           = var.loki_log_retention_days
  cpu                          = var.loki_cpu
  memory                       = var.loki_memory
  container_memory             = var.loki_container_memory
  container_memory_reservation = var.loki_container_memory_reservation
  desired_count                = var.desired_count

  aws_region = var.aws_region
}

# OpenTelemetry Collector Service
module "otelcol" {
  source = "../../modules/services/monitoring/otelcol"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  otelcol_image = var.monitoring_otelcol_image

  # Resource configuration
  cpu                          = var.otelcol_cpu
  memory                       = var.otelcol_memory
  container_memory             = var.otelcol_container_memory
  container_memory_reservation = var.otelcol_container_memory_reservation
  desired_count                = var.desired_count


  aws_region = var.aws_region

  # No dependencies needed with localhost
}

# Grafana Service
module "grafana" {
  source = "../../modules/services/monitoring/grafana"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  target_group_arn   = data.terraform_remote_state.shared.outputs.monitoring_target_group_arn
  alb_listener       = null
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  grafana_image   = var.grafana_image
  grafana_version = var.grafana_version
  grafana_domain  = var.grafana_domain
  grafana_plugins = var.grafana_plugins
  admin_password  = var.grafana_admin_password

  # Grafana 리소스 설정
  cpu                          = var.grafana_cpu
  memory                       = var.grafana_memory
  container_memory             = var.grafana_container_memory
  container_memory_reservation = var.grafana_container_memory_reservation
  desired_count                = var.grafana_desired_count

  aws_region = var.aws_region

  # No dependencies needed with localhost
}

# Prometheus Service
module "prometheus" {
  source = "../../modules/services/monitoring/prometheus"

  environment        = "monitoring"
  ecs_cluster_id     = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_execution_role_arn
  task_role_arn      = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  prometheus_image  = var.monitoring_prometheus_image
  prometheus_domain = var.prometheus_domain
  target_group_arn  = var.prometheus_target_group_arn
  alb_listener      = null

  # Resource configuration
  cpu                          = var.prometheus_cpu
  memory                       = var.prometheus_memory
  container_memory             = var.prometheus_container_memory
  container_memory_reservation = var.prometheus_container_memory_reservation
  desired_count                = var.desired_count

  # Storage configuration
  metrics_retention_days = var.prometheus_metrics_retention_days
  local_retention_time   = var.prometheus_local_retention_time
  local_retention_size   = var.prometheus_local_retention_size

  # Prometheus settings
  scrape_interval     = var.prometheus_scrape_interval
  evaluation_interval = var.prometheus_evaluation_interval
  log_level           = var.prometheus_log_level

  # Integration endpoints - using localhost
  otelcol_endpoint = "localhost:8888"

  aws_region = var.aws_region

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

  rds_endpoint      = var.rds_endpoint
  database_username = var.rds_database_username
  database_password = var.rds_database_password
}

#################################
# ECR - 모니터링 커스텀 이미지 (config baking, groble-images가 push)
#################################
module "ecr" {
  source = "../../modules/platform/ecr"

  project_name = "groble"

  # 이 환경은 범용(모니터링) 레포만 생성. spring-api 레포는 dev/prod가 소유.
  create_prod_repository = false
  create_dev_repository  = false

  # baking 태그(<버전>-<config해시>) 덮어쓰기 방지
  image_tag_mutability  = "IMMUTABLE"
  enable_image_scanning = true
  encryption_type       = "AES256"

  generic_repositories = {
    "groble-prometheus" = 10
    "groble-otelcol"    = 10
    "groble-loki"       = 10
  }

  # ECS 실행/태스크 역할에 pull 허용
  allowed_principals = [
    data.terraform_remote_state.shared.outputs.ecs_execution_role_arn,
    data.terraform_remote_state.shared.outputs.ecs_task_role_arn,
  ]
}

output "monitoring_ecr_repository_urls" {
  description = "모니터링 이미지 push 대상 ECR URL (groble-images CI에서 사용)"
  value       = module.ecr.generic_repository_urls
}

#################################
# GitHub Actions OIDC - groble-images CI가 access key 없이 ECR push
#################################
module "github_oidc" {
  source = "../../modules/platform/github-oidc"

  github_org  = "TEAM-LIAISON"
  github_repo = "groble-images"
  role_name   = "groble-images-ci"

  # 3개 모니터링 레포에만 push/pull 허용
  ecr_repository_arns = values(module.ecr.generic_repository_arns)

  # TerraformPowerUser 권한셋에 OIDC provider 액션을 추가했으므로 Terraform이 직접 생성.
  create_oidc_provider = true

  # GitHub이 immutable subject claim(@조직ID/@레포ID 삽입)으로 롤아웃 중이라
  # mutable/immutable 두 형태를 모두 허용해야 sts:AssumeRoleWithWebIdentity가 성공한다.
  subject_claims = [
    "repo:TEAM-LIAISON/groble-images:*",
    "repo:TEAM-LIAISON@156536067/groble-images@1304692487:*",
  ]
}

output "github_actions_ci_role_arn" {
  description = "groble-images 워크플로의 role-to-assume 값"
  value       = module.github_oidc.role_arn
}
