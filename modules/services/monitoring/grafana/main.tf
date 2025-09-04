# Task Definition for Host Mode (simplified)
resource "aws_ecs_task_definition" "grafana" {
  family                = "${var.environment}-grafana"
  network_mode          = "host"  # Host Mode for localhost communication
  requires_compatibilities = ["EC2"]
  cpu                   = var.cpu
  memory                = var.memory
  execution_role_arn    = var.execution_role_arn
  task_role_arn         = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "${var.grafana_image}:${var.grafana_version}"
      
      # Host networking - expose port for load balancer
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      # 메모리 설정 (낮은 리소스 사용)
      memory = var.container_memory
      memoryReservation = var.container_memory_reservation

      environment = [
        {
          name  = "GF_SECURITY_ADMIN_PASSWORD"
          value = var.admin_password
        },
        {
          name  = "GF_USERS_ALLOW_SIGN_UP"
          value = "false"
        },
        {
          name  = "GF_SERVER_DOMAIN"
          value = var.grafana_domain
        },
        {
          name  = "GF_SERVER_ROOT_URL"
          value = "https://${var.grafana_domain}"
        },
        {
          name  = "GF_INSTALL_PLUGINS"
          value = var.grafana_plugins
        },
        # 로깅 비활성화 (비용 절감)
        {
          name  = "GF_LOG_LEVEL"
          value = "warn"
        }
      ]

      # 로깅 설정 제거 (CloudWatch 사용 안함)
      logConfiguration = {
        logDriver = "json-file"
        options = {
          "max-size" = "10m"
          "max-file" = "3"
        }
      }

      essential = true

      # Health check using wget
      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-grafana-task"
    Environment = var.environment
    Service     = "monitoring"
  }
}


# ECS Service for Grafana (EC2 + Bridge Mode)
resource "aws_ecs_service" "grafana" {
  name            = "${var.environment}-grafana"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.desired_count
  
  # Host 모드에서 포트 충돌 방지를 위한 배포 설정
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # 모니터링 EC2에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [var.alb_listener]

  tags = {
    Name        = "${var.environment}-grafana-service"
    Environment = var.environment
    Service     = "monitoring"
  }
}