#################################
# CodeDeploy 애플리케이션
#################################

# CodeDeploy 애플리케이션 생성
resource "aws_codedeploy_app" "app" {
  compute_platform = "ECS"
  name             = "${var.project_name}-app"

  tags = {
    Name = "${var.project_name}-codedeploy-app"
  }
}

#################################
# CodeDeploy 배포 그룹 - Production
#################################

resource "aws_codedeploy_deployment_group" "prod_deployment_group" {
  count                  = var.create_prod_deployment_group ? 1 : 0
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "${var.project_name}-prod-deployment-group"
  service_role_arn      = var.codedeploy_service_role_arn
  deployment_config_name = var.prod_deployment_config

  # ECS 배포를 위한 필수 설정
  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  # ECS 서비스 설정
  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.prod_service_name
  }

  # Blue/Green 배포 설정 (ECS 전용)
  blue_green_deployment_config {
    # 배포 준비 옵션
    deployment_ready_option {
      action_on_timeout    = var.deployment_ready_timeout_action
      wait_time_in_minutes = var.deployment_ready_wait_time
    }

    # 트래픽 라우팅 설정
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time
    }
  }

  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = var.prod_blue_target_group_name
      }

      target_group {
        name = var.prod_green_target_group_name
      }

      prod_traffic_route {
        listener_arns = var.prod_listener_arns
      }

      test_traffic_route {
        listener_arns = var.test_listener_arns
      }
    }
  }

  # 자동 롤백 설정
  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = var.auto_rollback_events
  }

  # 알람 설정
  alarm_configuration {
    enabled = var.enable_alarm_configuration
    alarms  = var.alarm_names
  }

  tags = {
    Name        = "${var.project_name}-prod-deployment-group"
    Environment = "production"
  }

  # ECS 서비스 의존성은 상위 모듈에서 관리
  # depends_on은 정적 리소스 참조만 가능하므로 제거
}

#################################
# CodeDeploy 배포 그룹 - Development
#################################

resource "aws_codedeploy_deployment_group" "dev_deployment_group" {
  count                  = var.create_dev_deployment_group ? 1 : 0
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "${var.project_name}-dev-deployment-group"
  service_role_arn      = var.codedeploy_service_role_arn
  deployment_config_name = var.dev_deployment_config

  # ECS 배포를 위한 필수 설정
  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  # ECS 서비스 설정
  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.dev_service_name
  }

  # Blue/Green 배포 설정 (ECS 전용)
  blue_green_deployment_config {
    # 배포 준비 옵션
    deployment_ready_option {
      action_on_timeout    = var.deployment_ready_timeout_action
      wait_time_in_minutes = var.deployment_ready_wait_time
    }

    # 트래픽 라우팅 설정
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time
    }
  }

  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = var.dev_blue_target_group_name
      }
      target_group {
        name = var.dev_green_target_group_name
      }

      prod_traffic_route {
        listener_arns = var.prod_listener_arns
      }

      test_traffic_route {
        listener_arns = var.test_listener_arns
      }
    }
  }

  # 자동 롤백 설정
  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = var.auto_rollback_events
  }

  # 알람 설정
  alarm_configuration {
    enabled = var.enable_alarm_configuration
    alarms  = var.alarm_names
  }

  tags = {
    Name        = "${var.project_name}-dev-deployment-group"
    Environment = "development"
  }

  # ECS 서비스 의존성은 상위 모듈에서 관리
  # depends_on은 정적 리소스 참조만 가능하므로 제거
}

#################################
# S3 버킷 (CodeDeploy 아티팩트 저장용)
#################################

resource "aws_s3_bucket" "codedeploy_artifacts" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = "${var.project_name}-codedeploy-artifacts-${random_string.bucket_suffix[0].result}"

  tags = {
    Name    = "${var.project_name}-codedeploy-artifacts"
    Purpose = "CodeDeploy artifacts storage"
  }
}

# S3 버킷 버전 관리
resource "aws_s3_bucket_versioning" "codedeploy_artifacts_versioning" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.codedeploy_artifacts[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy_artifacts_encryption" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.codedeploy_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 버킷 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "codedeploy_artifacts_pab" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.codedeploy_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 버킷 이름 고유성을 위한 랜덤 문자열
resource "random_string" "bucket_suffix" {
  count   = var.create_artifacts_bucket ? 1 : 0
  length  = 8
  special = false
  upper   = false
}
