#################################
# CodeDeploy 애플리케이션
#################################

# CodeDeploy 애플리케이션 생성
resource "aws_codedeploy_app" "groble_app" {
  compute_platform = "ECS"
  name             = "${var.project_name}-app"

  tags = {
    Name = "${var.project_name}-codedeploy-app"
  }
}

#################################
# CodeDeploy 배포 그룹 - Production
#################################

resource "aws_codedeploy_deployment_group" "groble_prod_deployment_group" {
  app_name               = aws_codedeploy_app.groble_app.name
  deployment_group_name  = "${var.project_name}-prod-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  # ECS 배포를 위한 필수 설정
  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  # ECS 서비스 설정 (Spring API 서비스만 Blue/Green 배포)
  ecs_service {
    cluster_name = aws_ecs_cluster.groble_cluster.name
    service_name = "${var.project_name}-prod-service"  # 실제 서비스 이름 사용
  }

  # Blue/Green 배포 설정 (ECS 전용)
  blue_green_deployment_config {
    # 배포 준비 옵션
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }

    # 트래픽 라우팅 설정
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = aws_lb_target_group.groble_prod_blue_tg.name
      }

      target_group {
        name = aws_lb_target_group.groble_prod_green_tg.name
      }

      prod_traffic_route {
        listener_arns = [aws_lb_listener.groble_https_listener.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.groble_https_test_listener.arn]
      }
    }
  }

  # 자동 롤백 설정
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  # 알람 설정 (옵션)
  alarm_configuration {
    enabled = false  # 필요 시 true로 변경하고 알람 추가
    alarms  = []
  }

  tags = {
    Name        = "${var.project_name}-prod-deployment-group"
    Environment = "production"
  }

  # ECS 서비스가 먼저 생성되도록 의존성 설정
  depends_on = [
    aws_ecs_service.groble_prod_service
  ]
}

#################################
# Development는 CodeDeploy 사용 안함 (메모리 절약)
#################################

# Development 환경은 ECS 네이티브 Rolling 배포 사용
# t2.micro 인스턴스에서 Blue/Green 배포는 메모리 부족으로 제거

#################################
# CodeDeploy 배포 설정 (사전 정의된 설정 사용)
#################################

# 사전 정의된 배포 설정 사용
# Production: 카나리 배포 (25% -> 100%)
# Development: 즉시 배포 (All at once)

#################################
# S3 버킷 (CodeDeploy 아티팩트 저장용)
#################################

resource "aws_s3_bucket" "codedeploy_artifacts" {
  bucket = "${var.project_name}-codedeploy-artifacts-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-codedeploy-artifacts"
    Purpose     = "CodeDeploy artifacts storage"
  }
}

# S3 버킷 버전 관리
resource "aws_s3_bucket_versioning" "codedeploy_artifacts_versioning" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy_artifacts_encryption" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 버킷 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "codedeploy_artifacts_pab" {
  bucket = aws_s3_bucket.codedeploy_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 버킷 이름 고유성을 위한 랜덤 문자열
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}