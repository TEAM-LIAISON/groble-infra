#################################
# Production Redis Task Definition & Service
#################################

# Redis Task Definition
resource "aws_ecs_task_definition" "redis_task" {
  family                   = "${var.project_name}-prod-redis-task"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-redis"
      image     = "redis:7-alpine"
      essential = true
      memory    = var.redis_memory
      cpu       = var.redis_cpu

      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }
      ]

      # Redis 설정 - 기존 단순 설정 유지
      healthCheck = {
        command     = ["CMD", "redis-cli", "ping"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  # 기존 단순 설정 유지 - 볼륨 없음

  tags = {
    Name        = "${var.project_name}-prod-redis-task"
    Environment = "production"
    Type        = "cache"
  }
}

# Redis Service
resource "aws_ecs_service" "redis_service" {
  name                = "${var.project_name}-prod-redis-service"
  cluster             = var.ecs_cluster_id
  task_definition     = "groble-prod-redis-task:38"  # 현재 revision 고정
  desired_count       = 1
  wait_for_steady_state = false
  
  launch_type = "EC2"

  # Production 인스턴스에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # 변경 방지를 위한 lifecycle 규칙
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count
    ]
  }

  tags = {
    Name        = "${var.project_name}-prod-redis-service"
    Environment = "production"
    Type        = "cache"
  }
}
