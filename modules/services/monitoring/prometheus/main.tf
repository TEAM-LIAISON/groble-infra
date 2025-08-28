# S3 접근 권한 추가 (기존 task role에 인라인 정책으로 추가)
resource "aws_iam_role_policy" "prometheus_s3_access" {
  name = "${var.environment}-prometheus-s3-access"
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
          aws_s3_bucket.prometheus_storage.arn,
          "${aws_s3_bucket.prometheus_storage.arn}/*"
        ]
      }
    ]
  })
}

# S3 Bucket for Prometheus long-term storage
resource "aws_s3_bucket" "prometheus_storage" {
  bucket = "${var.environment}-prometheus-storage-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.environment}-prometheus-storage"
    Environment = var.environment
    Service     = "monitoring"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "prometheus_storage" {
  bucket = aws_s3_bucket.prometheus_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prometheus_storage" {
  bucket = aws_s3_bucket.prometheus_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Generate Prometheus configuration from template
locals {
  prometheus_config = templatefile("${path.module}/config/prometheus.yml", {
    aws_region          = var.aws_region
    scrape_interval     = var.scrape_interval
    evaluation_interval = var.evaluation_interval
  })
}

# Write the templated configuration to a local file for deployment
resource "local_file" "prometheus_config" {
  content  = local.prometheus_config
  filename = "${path.module}/config/rendered-prometheus.yml"
}

resource "aws_s3_bucket_lifecycle_configuration" "prometheus_storage" {
  bucket = aws_s3_bucket.prometheus_storage.id

  rule {
    id     = "prometheus_metrics_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.metrics_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Task Definition for Prometheus
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.environment}-prometheus"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn           = var.task_role_arn

  # Volume for Prometheus data (local storage)
  volume {
    name      = "prometheus-data"
    host_path = "/opt/prometheus/data"
  }

  container_definitions = jsonencode([
    # Init container to fix permissions
    {
      name  = "init-prometheus"
      image = "busybox:latest"
      essential = false
      
      mountPoints = [
        {
          sourceVolume  = "prometheus-data"
          containerPath = "/prometheus"
          readOnly      = false
        }
      ]
      
      command = [
        "sh", "-c",
        "mkdir -p /prometheus && chown -R 65534:65534 /prometheus && chmod -R 755 /prometheus"
      ]
      
      logDriver = "json-file"
      logOptions = {
        "max-size" = "5m"
        "max-file" = "2"
      }
    },
    {
      name  = "prometheus"
      image = "${var.prometheus_image}:${var.prometheus_version}"
      
      # Depend on init container
      dependsOn = [
        {
          containerName = "init-prometheus"
          condition = "SUCCESS"
        }
      ]
      
      # Host networking - no port mappings needed

      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Volume mounts
      mountPoints = [
        {
          sourceVolume  = "prometheus-data"
          containerPath = "/prometheus"
          readOnly      = false
        }
      ]

      # Environment variables for Prometheus configuration
      environment = [
        {
          name  = "PROMETHEUS_CONFIG_YAML"
          value = local.prometheus_config
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      # Run as prometheus user (UID 65534)
      user = "65534:65534"

      # Prometheus startup command - create config and start
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
        echo 'Creating Prometheus config in writable location...' &&
        echo "$PROMETHEUS_CONFIG_YAML" > /tmp/prometheus.yml &&
        echo 'Prometheus config created:' &&
        cat /tmp/prometheus.yml &&
        echo 'Starting Prometheus with localhost config...' &&
        /bin/prometheus --config.file=/tmp/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=${var.local_retention_time} --storage.tsdb.retention.size=${var.local_retention_size} --web.console.libraries=/etc/prometheus/console_libraries --web.console.templates=/etc/prometheus/consoles --web.enable-lifecycle --web.enable-admin-api --web.external-url=https://${var.prometheus_domain} --web.route-prefix=/ --log.level=${var.log_level}
        EOT
      ]

      # Logging configuration
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
          "wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-prometheus-task"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "prometheus"
  }
}

# ECS Service for Prometheus
resource "aws_ecs_service" "prometheus" {
  name            = "${var.environment}-prometheus"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.prometheus.family
  desired_count   = var.desired_count
  
  # Deploy only to monitoring EC2 instances
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  # No service discovery needed with host networking

  # Load balancer configuration (optional)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != "" ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = "prometheus"
      container_port   = 9090
    }
  }

  # Service update configuration
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # Health check grace period
  health_check_grace_period_seconds = var.health_check_grace_period

  depends_on = [var.alb_listener]

  tags = {
    Name        = "${var.environment}-prometheus-service"
    Environment = var.environment
    Service     = "monitoring"
    Component   = "prometheus"
  }
}