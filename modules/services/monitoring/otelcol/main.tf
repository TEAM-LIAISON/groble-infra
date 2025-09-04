# Generate OpenTelemetry Collector configuration from template
locals {
  otelcol_config = templatefile("${path.module}/config/otelcol-config.yaml", {
    collector_version = var.otelcol_version
    aws_region       = var.aws_region
  })
}

# Task Definition for OpenTelemetry Collector
resource "aws_ecs_task_definition" "otelcol" {
  family                   = "${var.environment}-otelcol"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn           = var.task_role_arn



  # Volume for temporary config storage
  volume {
    name = "tmp-volume"
    host_path = "/tmp"
  }

  container_definitions = jsonencode([
    # Init container to create config file
    {
      name  = "otelcol-init"
      image = "busybox:latest"
      essential = false
      
      mountPoints = [
        {
          sourceVolume  = "tmp-volume"
          containerPath = "/tmp"
          readOnly      = false
        }
      ]
      
      environment = [
        {
          name  = "OTELCOL_CONFIG_YAML"
          value = local.otelcol_config
        }
      ]
      
      command = [
        "sh", "-c",
        "echo \"$OTELCOL_CONFIG_YAML\" > /tmp/otelcol-config.yaml && echo 'Config file created at /tmp/otelcol-config.yaml' && ls -la /tmp/otelcol-config.yaml"
      ]
      
      logDriver = "json-file"
      logOptions = {
        "max-size" = "5m"
        "max-file" = "2"
      }
    },
    {
      name  = "otelcol"
      image = "${var.otelcol_image}:${var.otelcol_version}"
      
      # Depend on init container
      dependsOn = [
        {
          containerName = "otelcol-init"
          condition = "SUCCESS"
        }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "tmp-volume"
          containerPath = "/tmp"
          readOnly      = true
        }
      ]

      # Memory configuration
      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation


      # OpenTelemetry Collector startup - use config from shared volume
      command = [
        "--config=/tmp/otelcol-config.yaml"
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

      # Logging configuration
      logDriver = "json-file"
      logOptions = {
        "max-size" = "10m"
        "max-file" = "3"
      }

      essential = true

      # Health check configuration
      # healthCheck = {
      #   command = [
      #     "CMD-SHELL",
      #     "wget --no-verbose --tries=1 --spider http://localhost:13133/ || exit 1"
      #   ]
      #   interval    = var.health_check_interval
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 30
      # }
    }
  ])

  tags = {
    Name        = "${var.environment}-otelcol-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "opentelemetry-collector"
  }
}

# Write the templated configuration to a local file for deployment
resource "local_file" "otelcol_config" {
  content  = local.otelcol_config
  filename = "${path.module}/config/rendered-otelcol-config.yaml"
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