# Grafana Module

This module deploys Grafana as an ECS service on EC2 instances using host networking mode.

## Features

- **Low Resource Usage**: Configured for 0.25 vCPU and 256MB memory
- **Host Mode Networking**: Direct communication with monitoring stack
- **Placement Constraints**: Deploys only on monitoring EC2 instances
- **Cost Optimized**: No CloudWatch logs or EBS volumes
- **Plugin Support**: Configurable plugin installation

## Usage

```hcl
module "grafana" {
  source = "../../modules/services/monitoring/grafana"

  environment            = "monitoring"
  ecs_cluster_id        = var.ecs_cluster_id
  target_group_arn      = aws_lb_target_group.grafana.arn
  alb_listener          = aws_lb_listener_rule.grafana
  execution_role_arn    = var.execution_role_arn
  task_role_arn         = var.task_role_arn

  grafana_image         = "grafana/grafana"
  grafana_version       = "10.2.0"
  grafana_domain        = "grafana.example.com"
  admin_password        = "secure-password"
  
  cpu                         = 250
  memory                      = 256
  container_memory           = 256
  container_memory_reservation = 128
  desired_count              = 1
  
  aws_region            = "ap-northeast-2"
}
```

## Requirements

- ECS Cluster with EC2 instances
- EC2 instances tagged with `attribute:environment == monitoring`
- ALB Target Group for Grafana (optional for external access)
- IAM roles for ECS execution and task
- Host mode networking for localhost communication

## Outputs

- `ecs_service_arn`: ARN of the Grafana ECS service
- `ecs_service_name`: Name of the Grafana ECS service
- `task_definition_arn`: ARN of the Grafana task definition
