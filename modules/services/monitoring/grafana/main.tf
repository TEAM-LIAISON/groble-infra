# Task Definition for Bridge Mode (경량화)
resource "aws_ecs_task_definition" "grafana" {
  family                = "${var.environment}-grafana"
  network_mode          = "bridge"  # Bridge Mode 사용
  requires_compatibilities = ["EC2"]  # EC2 타입 사용
  cpu                   = var.cpu
  memory                = var.memory
  execution_role_arn    = var.execution_role_arn
  task_role_arn         = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "${var.grafana_image}:${var.grafana_version}"
      
      # Bridge Mode에서는 hostPort 설정
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000  # 고정 포트 할당
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
      logDriver = "json-file"
      logOptions = {
        "max-size" = "10m"
        "max-file" = "3"
      }

      essential = true
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