#################################
# ECS 서비스 - Production MySQL
#################################

resource "aws_ecs_service" "groble_prod_mysql_service" {
  name            = "${var.project_name}-prod-mysql-service"
  cluster         = aws_ecs_cluster.groble_cluster.id
  task_definition = aws_ecs_task_definition.groble_prod_mysql_task.arn
  desired_count   = 1
  
  launch_type = "EC2"

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == production"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # 지속적 서비스 - Blue/Green 배포하지 않음
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

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

  # awsvpc 모드 필수 네트워크 설정 - Public Subnet 사용 (EC2 인스턴스 설정 따름)
  network_configuration {
    subnets          = [aws_subnet.groble_vpc_public[0].id]
    security_groups  = [aws_security_group.groble_api_task_sg.id]
    # assign_public_ip = EC2 launch type에서는 지원하지 않음 - EC2 인스턴스 설정을 따름
  }

  # CodeDeploy를 위한 Deployment Controller 설정
  deployment_controller {
    type = "CODE_DEPLOY"
  }

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

  # awsvpc 모드 필수 네트워크 설정 - Public Subnet 사용 (EC2 인스턴스 설정 따름)
  network_configuration {
    subnets          = [aws_subnet.groble_vpc_public[1].id]
    security_groups  = [aws_security_group.groble_api_task_sg.id]
    # assign_public_ip = EC2 launch type에서는 지원하지 않음 - EC2 인스턴스 설정을 따름
  }

  # ECS 네이티브 배포 사용 (CodeDeploy 제거)
  # deployment_controller 블록 제거로 기본 ECS 배포 사용

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == development"
  }

  # Rolling 배포를 위한 설정 (t2.micro 메모리 고려)
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # ALB 타겟 그룹 연결 (단일 타겟 그룹)
  load_balancer {
    target_group_arn = aws_lb_target_group.groble_dev_tg.arn
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
