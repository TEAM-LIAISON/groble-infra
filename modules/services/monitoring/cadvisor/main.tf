# Task Definition for cAdvisor (DAEMON mode for global deployment)
resource "aws_ecs_task_definition" "cadvisor" {
  family                   = "${var.environment}-cadvisor"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # Volumes for container metrics collection
  volume {
    name      = "rootfs"
    host_path = "/"
  }

  volume {
    name      = "var-run"
    host_path = "/var/run"
  }

  volume {
    name      = "sys"
    host_path = "/sys"
  }

  volume {
    name      = "docker"
    host_path = "/var/lib/docker"
  }

  volume {
    name      = "disk"
    host_path = "/dev/disk"
  }

  container_definitions = jsonencode([
    {
      name  = "cadvisor"
      image = "${var.cadvisor_image}:${var.cadvisor_version}"

      # Host networking - exposes on port 8081 to avoid conflict with API server on 8080
      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Privileged mode required for container metrics
      privileged = true

      # Mount host filesystems for container metrics collection
      mountPoints = [
        {
          sourceVolume  = "rootfs"
          containerPath = "/rootfs"
          readOnly      = true
        },
        {
          sourceVolume  = "var-run"
          containerPath = "/var/run"
          readOnly      = false
        },
        {
          sourceVolume  = "sys"
          containerPath = "/sys"
          readOnly      = true
        },
        {
          sourceVolume  = "docker"
          containerPath = "/var/lib/docker"
          readOnly      = true
        },
        {
          sourceVolume  = "disk"
          containerPath = "/dev/disk"
          readOnly      = true
        }
      ]

      # cAdvisor command arguments - use port 8081 instead of default 8080
      command = [
        "--port=8081",
        "--housekeeping_interval=30s",
        "--docker_only=true",
        "--store_container_labels=false",
        "--whitelisted_container_labels=com.amazonaws.ecs.cluster,com.amazonaws.ecs.container-name,com.amazonaws.ecs.task-definition-family"
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

      # Health check on port 8081
      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:8081/healthz || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-cadvisor-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "cadvisor"
  }
}

# ECS Service for cAdvisor (DAEMON scheduling)
resource "aws_ecs_service" "cadvisor" {
  name            = "${var.environment}-cadvisor"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.cadvisor.arn

  # DAEMON scheduling strategy - one task per EC2 instance
  scheduling_strategy = "DAEMON"

  # Service update configuration
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  tags = {
    Name        = "${var.environment}-cadvisor-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "cadvisor"
  }
}
