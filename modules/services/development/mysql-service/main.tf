#################################
# Development MySQL Task Definition & Service
#################################

# MySQL Task Definition
resource "aws_ecs_task_definition" "mysql_task" {
  family                   = "${var.project_name}-dev-mysql-task"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-mysql"
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
        },
        {
          name  = "MYSQL_INNODB_BUFFER_POOL_SIZE"
          value = "128M"  # 기존 설정
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
          sourceVolume  = "mysql-dev-data"
          containerPath = "/var/lib/mysql"
          readOnly      = false
        }
      ]
    }
  ])

  # 데이터 영속성을 위한 볼륨 정의
  volume {
    name      = "mysql-dev-data"
    host_path = "/opt/mysql-dev-data"
  }

  tags = {
    Name        = "${var.project_name}-dev-mysql-task"
    Environment = "development"
    Type        = "database"
  }
}

# MySQL Service
resource "aws_ecs_service" "mysql_service" {
  name            = "${var.project_name}-dev-mysql-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.mysql_task.arn
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
    Name        = "${var.project_name}-dev-mysql-service"
    Environment = "development"
    Type        = "database"
  }
}
