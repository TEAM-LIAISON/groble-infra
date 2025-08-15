#################################
# Development API Task Definition & Service
#################################

# API Task Definition
resource "aws_ecs_task_definition" "api_task" {
  family                   = "${var.project_name}-dev-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-spring-api"
      image     = var.spring_app_image
      essential = true
      memoryReservation = var.memory_reservation
      memory    = var.memory_limit
      cpu       = var.cpu

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PROFILES"
          value = var.spring_profiles
        },
        {
          name  = "ENV"
          value = var.server_env
        },
        {
          name  = "APP_NAME"
          value = var.project_name
        },
        {
          name  = "DB_HOST"
          value = var.db_host
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = var.mysql_database
        },
        {
          name  = "DB_USERNAME"
          value = "groble_root"
        },
        {
          name  = "DB_PASSWORD"
          value = var.mysql_root_password
        },
        {
          name  = "REDIS_HOST"
          value = var.redis_host
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-dev-task"
    Environment = "development"
    Type        = "application"
  }
}

# API Service
resource "aws_ecs_service" "api_service" {
  name            = "${var.project_name}-dev-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.api_task.arn
  desired_count   = var.desired_count
  
  launch_type = "EC2"

  # CodeDeploy Blue/Green 배포 컨트롤러
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  # Development 인스턴스에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Network configuration for awsvpc mode
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  # Load balancer configuration required for CODE_DEPLOY
  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "${var.project_name}-dev-spring-api"
    container_port   = 8080
  }

  # 배포 중단 방지 - CodeDeploy가 load balancer와 task definition을 관리
  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }

  tags = {
    Name        = "${var.project_name}-dev-service"
    Environment = "development"
    Type        = "application"
  }
}
