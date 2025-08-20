# Note: SSM Parameter and related IAM policies removed - using environment variable approach instead

# S3 접근 권한 추가 (기존 task role에 인라인 정책으로 추가)
resource "aws_iam_role_policy" "loki_s3_access" {
  name = "${var.environment}-loki-s3-access"
  role = split("/", var.task_role_arn)[1]  # Extract role name from ARN

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
      days = 14
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Task Definition for Loki (Bridge Mode)
resource "aws_ecs_task_definition" "loki" {
  family                = "${var.environment}-loki"
  network_mode          = "bridge"  # Bridge Mode 사용
  requires_compatibilities = ["EC2"]  # EC2 타입 사용
  cpu                   = var.cpu
  memory                = var.memory
  execution_role_arn    = var.execution_role_arn
  task_role_arn         = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = "loki"
      image = "${var.loki_image}:${var.loki_version}"
      
      # Bridge Mode port mapping
      portMappings = [
        {
          containerPort = 3100
          hostPort      = 3100
          protocol      = "tcp"
        }
      ]

      # Memory settings
      memory = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Environment variable with Loki configuration
      environment = [
        {
          name  = "LOKI_CONFIG_YAML"
          value = templatefile("${path.module}/config/loki-config.yaml", {
            aws_region = var.aws_region
            s3_bucket  = aws_s3_bucket.loki_storage.bucket
          })
        }
      ]

      # Create config file from environment variable and start Loki
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "echo \"$LOKI_CONFIG_YAML\" > /etc/loki/loki-config.yaml && echo 'Config file created successfully:' && cat /etc/loki/loki-config.yaml && /usr/bin/loki -config.file=/etc/loki/loki-config.yaml"
      ]

      # Logging
      logDriver = "json-file"
      logOptions = {
        "max-size" = "10m"
        "max-file" = "3"
      }

      essential = true

      # Health check
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

# ECS Service for Loki (EC2 + Bridge Mode)
resource "aws_ecs_service" "loki" {
  name            = "${var.environment}-loki"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = var.desired_count
  
  # 모니터링 EC2에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  # Service Discovery 설정 (Bridge 모드에서는 container_name과 container_port 필수)
  service_registries {
    registry_arn   = aws_service_discovery_service.loki.arn
    container_name = "loki"
    container_port = 3100
  }

  tags = {
    Name        = "${var.environment}-loki-service"
    Environment = var.environment
    Service     = "monitoring"
  }
}

# Service Discovery for Loki
resource "aws_service_discovery_service" "loki" {
  name = "loki"

  dns_config {
    namespace_id = var.service_discovery_namespace_id
    
    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  tags = {
    Name        = "${var.environment}-loki-discovery"
    Environment = var.environment
    Service     = "monitoring"
  }
}
