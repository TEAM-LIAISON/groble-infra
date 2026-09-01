# 이름은 한 곳에서 만든다 — task definition family · ECS 서비스 이름 · 태그가 같이 움직인다.
#
# 호출부가 dev·prod 양쪽 모두 environment = "monitoring" 을 넘긴다. exporter 가 도는
# 곳이 모니터링 노드이지 감시 대상 환경이 아니기 때문이다. 그래서 두 인스턴스를
# 가르는 것은 environment 가 아니라 name_suffix 다.
locals {
  name = "${var.environment}-rds-exporter${var.name_suffix}"
}

# Task Definition for RDS Exporter
resource "aws_ecs_task_definition" "rds_exporter" {
  family                   = local.name
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "rds-exporter"
      image = "${var.rds_exporter_image}:${var.rds_exporter_version}"

      # Command to run exporter with connection string
      command = [
        "--mysqld.address=${var.rds_endpoint}:3306",
        "--mysqld.username=${var.database_username}",
        "--web.listen-address=:${var.exporter_port}"
      ]

      # Host networking - 노드에서 이 포트가 유일해야 한다 (dev·prod exporter 공존)
      portMappings = [
        {
          containerPort = var.exporter_port
          hostPort      = var.exporter_port
          protocol      = "tcp"
        }
      ]

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Environment variables for RDS connection
      environment = [
        {
          name  = "MYSQLD_EXPORTER_PASSWORD"
          value = var.database_password
        }
      ]

      # Logging configuration
      logConfiguration = {
        logDriver = "json-file"
        options = {
          "max-size" = "10m"
          "max-file" = "3"
        }
      }

      essential = true

      # Health check
      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:${var.exporter_port}/metrics || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name        = "${local.name}-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "rds-exporter"
  }
}

# ECS Service for RDS Exporter (single instance on monitoring)
resource "aws_ecs_service" "rds_exporter" {
  name            = local.name
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.rds_exporter.arn
  desired_count   = 1

  # Deploy only to monitoring EC2 instance
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  # Service update configuration
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  tags = {
    Name        = "${local.name}-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "rds-exporter"
  }
}
