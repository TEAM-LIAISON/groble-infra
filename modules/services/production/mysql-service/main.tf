#################################
# Production MySQL Task Definition & Service
#################################

# MySQL Task Definition
resource "aws_ecs_task_definition" "mysql_task" {
  family                   = "${var.project_name}-prod-mysql-task"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-mysql"
      image     = "mysql:8.0"
      essential = true
      memory    = var.mysql_memory
      cpu       = var.mysql_cpu

      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = var.mysql_root_password
        },
        {
          name  = "MYSQL_DATABASE"
          value = var.mysql_database
        },
        {
          name  = "MYSQL_USER"
          value = "groble_root"
        },
        {
          name  = "MYSQL_PASSWORD"
          value = var.mysql_root_password
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD --silent"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 90
      }

      mountPoints = [
        {
          sourceVolume  = "mysql-prod-data"
          containerPath = "/var/lib/mysql"
          readOnly      = false
        }
      ]
    }
  ])

  # 데이터 영속성을 위한 볼륨 정의
  volume {
    name      = "mysql-prod-data"
    host_path = "/opt/mysql-prod-data"
  }

  tags = {
    Name        = "${var.project_name}-prod-mysql-task"
    Environment = "production"
    Type        = "database"
  }
}

# MySQL Service
resource "aws_ecs_service" "mysql_service" {
  name                = "${var.project_name}-prod-mysql-service"
  cluster             = var.ecs_cluster_id
  task_definition     = "groble-prod-mysql-task:42"  # 현재 revision 고정
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
    Name        = "${var.project_name}-prod-mysql-service"
    Environment = "production"
    Type        = "database"
  }
}
