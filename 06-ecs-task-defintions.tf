#################################
# ECS 태스크 정의 - Production MySQL
#################################

resource "aws_ecs_task_definition" "groble_prod_mysql_task" {
  family                   = "${var.project_name}-prod-mysql-task"
  network_mode             = "host"  # bridge에서 host로 변경 (ENI 절약)
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
          hostPort      = 3306  # host 모드에서는 동일한 포트
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

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-production"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "prod-mysql"
      #   }
      # }
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
  network_mode             = "host"  # bridge에서 host로 변경 (ENI 절약)
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-mysql"
      image     = "mysql:8.0"
      essential = true
      memory    = 256  # 512MB → 256MB (메모리 최적화)
      cpu       = 128  # 256 → 128 (CPU 최적화)

      portMappings = [
        {
          containerPort = 3306
          hostPort      = 3306  # host 모드에서는 동일한 포트
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
          value = var.mysql_dev_root_password  # 수정: prod -> dev
        },
        {
          name  = "MYSQL_INNODB_BUFFER_POOL_SIZE"
          value = "128M"  # 버퍼 풀 사이즈 최적화
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

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-development"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "dev-mysql"
      #   }
      # }
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
  network_mode             = "host"  # bridge에서 host로 변경 (ENI 절약)
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
          hostPort      = 6379  # host 모드에서는 동일한 포트
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

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-production"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "prod-redis"
      #   }
      # }
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
  network_mode             = "host"  # bridge에서 host로 변경 (ENI 절약)
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-redis"
      image     = "redis:7-alpine"
      essential = true
      memory    = 128  # 256MB → 128MB (메모리 최적화)
      cpu       = 64   # 128 → 64 (CPU 최적화)

      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379  # host 모드에서는 동일한 포트
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

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-development"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "dev-redis"
      #   }
      # }
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
          name  = "ENV"
          value = var.server_env_prod
        },
        {
          name  = "APP_NAME"
          value = var.project_name
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
        },
        {
          name  = "REDIS_HOST"
          value = aws_instance.groble_prod_instance[0].private_ip
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
        startPeriod = 120  # DB 연결 대기시간 증가 (90 -> 120초)
      }

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-production"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "prod-api"
      #   }
      # }
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
        startPeriod = 120  # DB 연결 대기시간 증가 (90 -> 120초)
      }

      # logConfiguration 제거 - CloudWatch Logs 사용하지 않음
      # logConfiguration = {
      #   logDriver = "awslogs"
      #   options = {
      #     "awslogs-group"         = "/ecs/${var.project_name}-development"
      #     "awslogs-region"        = var.aws_region
      #     "awslogs-stream-prefix" = "dev-api"
      #   }
      # }
    }
  ])

  tags = {
    Name        = "${var.project_name}-dev-task"
    Environment = "development"
    Type        = "application"
  }
}