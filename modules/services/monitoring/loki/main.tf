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
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Task Definition for Loki (Enhanced IMDSv2 support)
resource "aws_ecs_task_definition" "loki" {
  family                = "${var.environment}-loki"
  network_mode          = "host"
  requires_compatibilities = ["EC2"]
  cpu                   = var.cpu
  memory                = var.memory
  execution_role_arn    = var.execution_role_arn
  task_role_arn         = var.task_role_arn

  container_definitions = jsonencode([
    # Init container to fetch AWS credentials
    {
      name  = "aws-credentials-init"
      image = "amazon/aws-cli:latest"
      essential = false
      
      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_REGION" 
          value = var.aws_region
        },
        {
          name  = "AWS_EC2_METADATA_DISABLED"
          value = "false"
        },
        {
          name  = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
          value = ""
        },
        {
          name  = "ECS_CONTAINER_METADATA_URI_V4"
          value = ""
        },
        {
          name  = "ECS_CONTAINER_METADATA_URI"
          value = ""
        },
        {
          name  = "AWS_IMDSv2_ENABLED"
          value = "true"
        }
      ]
      
      entryPoint = ["sh", "-c"]
      command = [
        "echo 'Using EC2 instance credentials only...' && unset AWS_CONTAINER_CREDENTIALS_RELATIVE_URI && unset ECS_CONTAINER_METADATA_URI_V4 && unset ECS_CONTAINER_METADATA_URI && echo 'Testing EC2 metadata service...' && TOKEN=$(curl -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' http://169.254.169.254/latest/api/token) && curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/ && echo 'EC2 metadata service accessible' && aws sts get-caller-identity && echo 'AWS credentials available'"
      ]
      
      logDriver = "json-file"
      logOptions = {
        "max-size" = "5m"
        "max-file" = "2"
      }
    },
    {
      name  = "loki"
      image = "${var.loki_image}:${var.loki_version}"
      
      # Depend on init container
      dependsOn = [
        {
          containerName = "aws-credentials-init"
          condition = "SUCCESS"
        }
      ]
      
      # Host networking - no port mappings needed

      memory = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Environment variables for Loki configuration and AWS settings
      environment = [
        {
          name  = "LOKI_CONFIG_YAML"
          value = templatefile("${path.module}/config/loki-config.yaml", {
            aws_region = var.aws_region
            s3_bucket  = aws_s3_bucket.loki_storage.bucket
          })
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
        },
        {
          name  = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
          value = ""
        },
        {
          name  = "ECS_CONTAINER_METADATA_URI_V4"
          value = ""
        },
        {
          name  = "ECS_CONTAINER_METADATA_URI"
          value = ""
        }
      ]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "unset AWS_CONTAINER_CREDENTIALS_RELATIVE_URI && unset ECS_CONTAINER_METADATA_URI_V4 && unset ECS_CONTAINER_METADATA_URI && echo \"$LOKI_CONFIG_YAML\" > /etc/loki/loki-config.yaml && echo 'Config file created successfully:' && cat /etc/loki/loki-config.yaml && echo 'AWS region: $AWS_DEFAULT_REGION' && echo 'Starting Loki with S3 storage and EC2 credentials...' && /usr/bin/loki -config.file=/etc/loki/loki-config.yaml"
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
