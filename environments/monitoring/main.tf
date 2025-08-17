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
  
  # 낮은 리소스 설정
  cpu                         = var.cpu
  memory                      = var.memory
  container_memory           = var.container_memory
  container_memory_reservation = var.container_memory_reservation
  desired_count              = var.desired_count
  
  aws_region            = var.aws_region
}
