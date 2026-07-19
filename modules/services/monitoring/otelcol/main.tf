# Task Definition for OpenTelemetry Collector
# config는 이미지에 구워져 있음(/etc/otelcol/config.yaml). 동적 값은 AWS_REGION 하나뿐.
resource "aws_ecs_task_definition" "otelcol" {
  family                   = "${var.environment}-otelcol"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "otelcol"
      image = var.otelcol_image

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # config는 이미지에 baked. AWS_REGION 은 otelcol 네이티브 ${env:AWS_REGION} 로 확장.
      command = [
        "--config=/etc/otelcol/config.yaml"
      ]

      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      logDriver = "json-file"
      logOptions = {
        "max-size" = "10m"
        "max-file" = "3"
      }

      essential = true
    }
  ])

  tags = {
    Name        = "${var.environment}-otelcol-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "opentelemetry-collector"
  }
}

# ECS Service for OpenTelemetry Collector
resource "aws_ecs_service" "otelcol" {
  name            = "${var.environment}-otelcol"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.otelcol.arn
  desired_count   = var.desired_count

  # Deploy only to monitoring EC2 instances
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  # Service update configuration
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # Health check grace period
  health_check_grace_period_seconds = var.health_check_grace_period

  tags = {
    Name        = "${var.environment}-otelcol-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "opentelemetry-collector"
  }
}
