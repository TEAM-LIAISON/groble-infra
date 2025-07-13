#################################
# ECS 서비스들 (EC2 인스턴스 배포 후 활성화)
#################################

#################################
# ECS 서비스 - Production MySQL
#################################

resource "aws_ecs_service" "groble_prod_mysql_service" {
  name            = "${var.project_name}-prod-mysql-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_prod_mysql_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Production EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # 서비스 디스커버리 등록
  service_registries {
    registry_arn   = aws_service_discovery_service.prod_mysql.arn
    container_name = "groble-prod-mysql"
    container_port = 3306
  }

  depends_on = [
    aws_service_discovery_service.prod_mysql
  ]

  tags = {
    Name        = "${var.project_name}-prod-mysql-service"
    Environment = "production"
    Type        = "database"
  }
}

#################################
# ECS 서비스 - Development MySQL
#################################

resource "aws_ecs_service" "groble_dev_mysql_service" {
  name            = "${var.project_name}-dev-mysql-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_dev_mysql_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Development EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # 서비스 디스커버리 등록
  service_registries {
    registry_arn   = aws_service_discovery_service.dev_mysql.arn
    container_name = "groble-dev-mysql"
    container_port = 3306
  }

  depends_on = [
    aws_service_discovery_service.dev_mysql
  ]

  tags = {
    Name        = "${var.project_name}-dev-mysql-service"
    Environment = "development"
    Type        = "database"
  }
}

#################################
# ECS 서비스 - Production Redis
#################################

resource "aws_ecs_service" "groble_prod_redis_service" {
  name            = "${var.project_name}-prod-redis-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_prod_redis_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Production EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # 서비스 디스커버리 등록
  service_registries {
    registry_arn   = aws_service_discovery_service.prod_redis.arn
    container_name = "groble-prod-redis"
    container_port = 6379
  }

  depends_on = [
    aws_service_discovery_service.prod_redis
  ]

  tags = {
    Name        = "${var.project_name}-prod-redis-service"
    Environment = "production"
    Type        = "cache"
  }
}

#################################
# ECS 서비스 - Development Redis
#################################

resource "aws_ecs_service" "groble_dev_redis_service" {
  name            = "${var.project_name}-dev-redis-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_dev_redis_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Development EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # 서비스 디스커버리 등록
  service_registries {
    registry_arn   = aws_service_discovery_service.dev_redis.arn
    container_name = "groble-dev-redis"
    container_port = 6379
  }

  depends_on = [
    aws_service_discovery_service.dev_redis
  ]

  tags = {
    Name        = "${var.project_name}-dev-redis-service"
    Environment = "development"
    Type        = "cache"
  }
}

#################################
# ECS 서비스 - Production API Server
#################################

resource "aws_ecs_service" "groble_prod_service" {
  name            = "${var.project_name}-prod-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_prod_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Production EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  # Blue/Green 배포를 위한 설정
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # ALB 타겟 그룹 연결 (API Server 컨테이너)
  load_balancer {
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
    container_name   = "${var.project_name}-prod-spring-api"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.groble_https_listener,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_service.groble_prod_mysql_service,
    aws_ecs_service.groble_prod_redis_service
  ]

  tags = {
    Name        = "${var.project_name}-prod-service"
    Environment = "production"
    Type        = "application"
  }
}

#################################
# ECS 서비스 - Development API Server
#################################

resource "aws_ecs_service" "groble_dev_service" {
  name            = "${var.project_name}-dev-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_dev_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  # Development EC2에만 배치하도록 제한
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # Blue/Green 배포를 위한 설정
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # ALB 타겟 그룹 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
    container_name   = "${var.project_name}-dev-spring-api"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.groble_https_listener,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_service.groble_dev_mysql_service,
    aws_ecs_service.groble_dev_redis_service
  ]

  tags = {
    Name        = "${var.project_name}-dev-service"
    Environment = "development"
    Type        = "application"
  }
}
