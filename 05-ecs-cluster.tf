#################################
# ECS 클러스터
#################################

# ECS 클러스터 생성
resource "aws_ecs_cluster" "groble_cluster" {
  name = "${var.project_name}-cluster"
  
  # Container Insights
    setting {
      name  = "containerInsights"
      value = "enabled"  # CloudWatch Container Insights 활성화
    }
  
  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

#################################
# CloudWatch 로그 그룹
#################################

# Production 로그 그룹
resource "aws_cloudwatch_log_group" "groble_prod_logs" {
  name              = "/ecs/${var.project_name}-production"
  retention_in_days = 7
 
   tags = {
     Name        = "${var.project_name}-prod-logs"
     Environment = "production"
   }
}

# Development 로그 그룹
resource "aws_cloudwatch_log_group" "groble_dev_logs" {
  name              = "/ecs/${var.project_name}-development"
  retention_in_days = 3

  tags = {
    Name        = "${var.project_name}-dev-logs"
    Environment = "development"
  }
}

#################################
# ECS 태스크 정의 - Production MySQL
#################################

resource "aws_ecs_task_definition" "groble_prod_mysql_task" {
  family                   = "${var.project_name}-prod-mysql-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-mysql"
      image     = "mysql:8.0"
      essential = true
      memory    = 512
      cpu       = 256

      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306  # 고정 포트 - Production MySQL
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = var.mysql_prod_root_password
        },
        {
          name  = "MYSQL_DATABASE"
          value = var.mysql_prod_database
        },
        {
          name  = "MYSQL_USER"
          value = "groble_root"
        },
        {
          name  = "MYSQL_PASSWORD"
          value = var.mysql_prod_root_password
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

#################################
# ECS 태스크 정의 - Development MySQL
#################################

resource "aws_ecs_task_definition" "groble_dev_mysql_task" {
  family                   = "${var.project_name}-dev-mysql-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-mysql"
      image     = "mysql:8.0"
      essential = true
      memory    = 512
      cpu       = 256

      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306  # 고정 포트 - Development MySQL (다른 EC2에서 실행되므로 동일 포트 사용 가능)
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "MYSQL_ROOT_PASSWORD"
          value = var.mysql_dev_root_password
        },
        {
          name  = "MYSQL_DATABASE"
          value = var.mysql_dev_database
        },
        {
          name  = "MYSQL_USER"
          value = "groble_root"
        },
        {
          name  = "MYSQL_PASSWORD"
          value = var.mysql_prod_root_password
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

#################################
# ECS 태스크 정의 - Production Redis
#################################

resource "aws_ecs_task_definition" "groble_prod_redis_task" {
  family                   = "${var.project_name}-prod-redis-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-redis"
      image     = "redis:7-alpine"
      essential = true
      memory    = 256
      cpu       = 128

      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379  # 고정 포트 - Production Redis
          protocol      = "tcp"
        }
      ]

      healthCheck = {
        command     = ["CMD", "redis-cli", "ping"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-prod-redis-task"
    Environment = "production"
    Type        = "cache"
  }
}

#################################
# ECS 태스크 정의 - Development Redis
#################################

resource "aws_ecs_task_definition" "groble_dev_redis_task" {
  family                   = "${var.project_name}-dev-redis-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-redis"
      image     = "redis:7-alpine"
      essential = true
      memory    = 256
      cpu       = 128

      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379  # 고정 포트 - Development Redis (다른 EC2에서 실행되므로 동일 포트 사용 가능)
          protocol      = "tcp"
        }
      ]

      healthCheck = {
        command     = ["CMD", "redis-cli", "ping"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-dev-redis-task"
    Environment = "development"
    Type        = "cache"
  }
}

#################################
# ECS 태스크 정의 - Production API Server
#################################

resource "aws_ecs_task_definition" "groble_prod_task" {
  family                   = "${var.project_name}-prod-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-spring-api"
      image     = var.spring_app_image_prod
      essential = true
      memory    = 512
      cpu       = 256

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PROFILES"
          value = var.spring_profiles_prod
        },
        {
          name  = "DB_HOST"
          value = aws_instance.groble_prod_instance[0].private_ip
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = var.mysql_prod_database
        },
        {
          name  = "DB_USERNAME"
          value = "groble_root"
        },
        {
          name  = "DB_PASSWORD"
          value = var.mysql_prod_root_password
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-production"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prod-api"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-prod-task"
    Environment = "production"
    Type        = "application"
  }
}

#################################
# ECS 태스크 정의 - Development API Server
#################################

resource "aws_ecs_task_definition" "groble_dev_task" {
  family                   = "${var.project_name}-dev-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-spring-api"
      image     = var.spring_app_image_dev
      essential = true
      memory    = 512
      cpu       = 256

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PROFILES"
          value = var.spring_profiles_dev
        },
        {
          name  = "ENV"
          value = var.server_env_dev
        },
        {
          name  = "APP_NAME"
          value = var.project_name
        },
        {
          name  = "DB_HOST"
          value = aws_instance.groble_develop_instance.private_ip
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = var.mysql_dev_database
        },
        {
          name  = "DB_USERNAME"
          value = "groble_root"
        },
        {
          name  = "DB_PASSWORD"
          value = var.mysql_dev_root_password
        },
        {
          name  = "REDIS_HOST"
          value = aws_instance.groble_develop_instance.private_ip
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-development"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "dev-api"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-dev-task"
    Environment = "development"
    Type        = "application"
  }
}