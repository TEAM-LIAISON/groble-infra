# Task Definition for RDS Exporter
resource "aws_ecs_task_definition" "rds_exporter" {
  family                   = "${var.environment}-rds-exporter"
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

      # Host networking - exposes on port 9042
      portMappings = [
        {
          containerPort = 9042
          hostPort      = 9042
          protocol      = "tcp"
        }
      ]

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Environment variables for RDS connection
      environment = [
        {
          name  = "DATA_SOURCE_NAME"
          value = "${var.database_username}:${var.database_password}@tcp(${var.rds_endpoint})/mysql"
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
          "wget --no-verbose --tries=1 --spider http://localhost:9042/metrics || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-rds-exporter-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "rds-exporter"
  }
}

# ECS Service for RDS Exporter (single instance on monitoring)
resource "aws_ecs_service" "rds_exporter" {
  name            = "${var.environment}-rds-exporter"
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
    Name        = "${var.environment}-rds-exporter-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "rds-exporter"
  }
}
