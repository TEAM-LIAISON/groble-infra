# S3 접근 권한 추가 (기존 task role에 인라인 정책으로 추가)
resource "aws_iam_role_policy" "loki_s3_access" {
  name = "${var.environment}-loki-s3-access"
  role = split("/", var.task_role_arn)[1] # Extract role name from ARN

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.loki_storage.arn,
          "${aws_s3_bucket.loki_storage.arn}/*"
        ]
      }
    ]
  })
}

# S3 Bucket for Loki storage
resource "aws_s3_bucket" "loki_storage" {
  bucket = "${var.environment}-loki-storage-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.environment}-loki-storage"
    Environment = var.environment
    Service     = "monitoring"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  rule {
    id     = "loki_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Task Definition for Loki (Enhanced IMDSv2 support)
resource "aws_ecs_task_definition" "loki" {
  family                   = "${var.environment}-loki"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "loki"
      image = var.loki_image

      # Host networking - no port mappings needed

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # config는 이미지에 baked(/etc/loki/config.yaml). 동적 값은 런타임 env로 주입하고
      # loki -config.expand-env=true 가 ${S3_BUCKET}/${AWS_REGION} 를 확장한다.
      environment = [
        {
          # 진짜 동적 값: S3 버킷명(random suffix). config의 ${S3_BUCKET} 로 확장됨.
          name  = "S3_BUCKET"
          value = aws_s3_bucket.loki_storage.bucket
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_METADATA_SERVICE_TIMEOUT"
          value = "10"
        },
        {
          name  = "AWS_METADATA_SERVICE_NUM_ATTEMPTS"
          value = "3"
        },
        {
          name  = "AWS_EC2_METADATA_V1_DISABLED"
          value = "false"
        },
        {
          name  = "AWS_SDK_LOAD_CONFIG"
          value = "1"
        },
        {
          name  = "AWS_IMDSv2_ENABLED"
          value = "true"
        },
        {
          name  = "AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE"
          value = "IPv4"
        },
        {
          name  = "AWS_EC2_METADATA_SERVICE_ENDPOINT"
          value = "http://169.254.169.254"
        },
        {
          name  = "AWS_CREDENTIAL_PROFILES_FILE"
          value = ""
        },
        {
          name  = "AWS_SHARED_CREDENTIALS_FILE"
          value = ""
        },
        {
          name  = "AWS_EC2_METADATA_DISABLED"
          value = "false"
        }
      ]

      # baked config를 직접 참조. ${S3_BUCKET}/${AWS_REGION} 는 expand-env로 런타임 확장.
      command = [
        "-config.file=/etc/loki/config.yaml",
        "-config.expand-env=true",
      ]

      logDriver = "json-file"
      logOptions = {
        "max-size" = "10m"
        "max-file" = "3"
      }

      essential = true

      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-loki-task"
    Environment = var.environment
    Service     = "monitoring"
  }
}

# ECS Service for Loki
resource "aws_ecs_service" "loki" {
  name            = "${var.environment}-loki"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = var.desired_count

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  # No service discovery needed with host networking

  # 서비스 업데이트 시 이전 태스크를 정상적으로 교체
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  tags = {
    Name        = "${var.environment}-loki-service"
    Environment = var.environment
    Service     = "monitoring"
  }
}

# Service discovery removed - using host networking with localhost
