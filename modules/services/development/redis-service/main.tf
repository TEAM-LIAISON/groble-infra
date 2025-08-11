#################################
# Development Redis Task Definition & Service
#################################

# Redis Task Definition
resource "aws_ecs_task_definition" "redis_task" {
  family                   = "${var.project_name}-dev-redis-task"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-redis"
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
    Name        = "${var.project_name}-dev-redis-task"
    Environment = "development"
    Type        = "cache"
  }
}

# Redis Service
resource "aws_ecs_service" "redis_service" {
  name            = "${var.project_name}-dev-redis-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.redis_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Development 인스턴스에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  tags = {
    Name        = "${var.project_name}-dev-redis-service"
    Environment = "development"
    Type        = "cache"
  }
}
