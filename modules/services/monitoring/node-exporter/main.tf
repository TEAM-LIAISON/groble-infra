# Task Definition for Node Exporter (DAEMON mode for global deployment)
resource "aws_ecs_task_definition" "node_exporter" {
  family                   = "${var.environment}-node-exporter"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # Volumes for host system access
  volume {
    name      = "proc"
    host_path = "/proc"
  }

  volume {
    name      = "sys"
    host_path = "/sys"
  }

  volume {
    name      = "rootfs"
    host_path = "/"
  }

  container_definitions = jsonencode([
    {
      name  = "node-exporter"
      image = "${var.node_exporter_image}:${var.node_exporter_version}"

      # Host networking - exposes on port 9100
      portMappings = [
        {
          containerPort = 9100
          hostPort      = 9100
          protocol      = "tcp"
        }
      ]

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Mount host filesystems for metrics collection
      mountPoints = [
        {
          sourceVolume  = "proc"
          containerPath = "/host/proc"
          readOnly      = true
        },
        {
          sourceVolume  = "sys"
          containerPath = "/host/sys"
          readOnly      = true
        },
        {
          sourceVolume  = "rootfs"
          containerPath = "/rootfs"
          readOnly      = true
        }
      ]

      # Node exporter command with host filesystem paths
      command = [
        "--path.procfs=/host/proc",
        "--path.sysfs=/host/sys",
        "--path.rootfs=/rootfs",
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
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
          "wget --no-verbose --tries=1 --spider http://localhost:9100/metrics || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-node-exporter-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "node-exporter"
  }
}

# ECS Service for Node Exporter (DAEMON scheduling)
resource "aws_ecs_service" "node_exporter" {
  name            = "${var.environment}-node-exporter"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.node_exporter.arn

  # DAEMON scheduling strategy - one task per EC2 instance
  scheduling_strategy = "DAEMON"

  # Service update configuration
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  tags = {
    Name        = "${var.environment}-node-exporter-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "node-exporter"
  }
}
