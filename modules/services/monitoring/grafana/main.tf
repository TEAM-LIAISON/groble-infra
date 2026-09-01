# Task Definition for Host Mode (simplified)
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.environment}-grafana"
  network_mode             = "host" # Host Mode for localhost communication
  requires_compatibilities = ["EC2"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # Volume for Grafana data persistence
  volume {
    name      = "grafana-data"
    host_path = "/opt/grafana/data"
  }

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "${var.grafana_image}:${var.grafana_version}"
      user  = "472:472" # Run as grafana user

      # Host networking - expose port for load balancer
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      # 메모리 설정 (낮은 리소스 사용)
      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation

      # Volume mounts for data persistence
      mountPoints = [
        {
          sourceVolume  = "grafana-data"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "GF_SECURITY_ADMIN_PASSWORD"
          value = var.admin_password
        },
        {
          name  = "GF_USERS_ALLOW_SIGN_UP"
          value = "false"
        },
        {
          name  = "GF_SERVER_DOMAIN"
          value = var.grafana_domain
        },
        {
          name  = "GF_SERVER_ROOT_URL"
          value = "https://${var.grafana_domain}"
        },
        {
          name  = "GF_INSTALL_PLUGINS"
          value = var.grafana_plugins
        },
        # 로깅 비활성화 (비용 절감)
        {
          name  = "GF_LOG_LEVEL"
          value = "warn"
        },
        # 알림 채널(SNS contact point)의 토픽 ARN.
        # 이미지의 provisioning/alerting/contact-points.yaml 이 ${...} 로 참조한다.
        # severity=critical -> prod 토픽(#groble-alert), warning -> dev 토픽(#groble-alert-dev)
        {
          name  = "GF_SNS_TOPIC_PROD"
          value = var.sns_topic_arn_prod
        },
        {
          name  = "GF_SNS_TOPIC_DEV"
          value = var.sns_topic_arn_dev
        }
      ]

      # 로깅 설정 제거 (CloudWatch 사용 안함)
      logConfiguration = {
        logDriver = "json-file"
        options = {
          "max-size" = "10m"
          "max-file" = "3"
        }
      }

      essential = true

      # Health check using wget
      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name        = "${var.environment}-grafana-task"
    Environment = var.environment
    Service     = "monitoring"
  }
}


# ECS Service for Grafana (EC2 + Bridge Mode)
resource "aws_ecs_service" "grafana" {
  name            = "${var.environment}-grafana"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.desired_count

  # Host 모드에서 포트 충돌 방지를 위한 배포 설정
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # 모니터링 EC2에만 배포
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:environment == monitoring"
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [var.alb_listener]

  tags = {
    Name        = "${var.environment}-grafana-service"
    Environment = var.environment
    Service     = "monitoring"
  }
}
#################################
# Grafana 알림 → SNS 발행 권한
#
# Grafana 11.x 의 네이티브 AWS SNS contact point 가 쓰는 권한이다.
# 이미지의 프로비저닝(contact-points.yaml)은 sigv4 에 액세스 키를 넣지 않고 비워둔다.
# 그러면 AWS SDK 기본 자격증명 체인을 타고, ECS 에서는 credential 프록시(169.254.170.2)를
# 거쳐 **이 Task Role** 로 해석된다. 즉 이미지에 시크릿을 넣지 않고 권한만으로 해결한다.
#
# ⚠️ 노드 재부팅으로 credential 프록시 iptables 가 사라지면 이 경로가 조용히 끊긴다.
#    (과거 Loki S3 적재 실패와 같은 원인) 알람이 안 오는 것으로 나타나므로 알아채기 어렵다.
#################################
# CloudWatch 읽기 — Grafana 의 CloudWatch 데이터소스용
#
# RDS 지표는 두 층으로 나뉜다. 엔진 계층(연결·쿼리·락·버퍼풀)은 mysqld_exporter →
# Prometheus 로 들어오지만, **AWS 자원 계층(CPU·FreeableMemory·FreeStorageSpace·
# IOPS·BurstBalance)은 CloudWatch 에만 있다.** 알람 12건이 임계 초과는 잡아 주지만
# "언제부터 그랬는가"를 그래프로 볼 수는 없었다.
#
# 인증은 별도 자격증명 없이 컨테이너 credential provider(169.254.170.2)를 쓴다.
# 같은 경로를 Grafana 의 SNS contact point 가 이미 쓰고 있어 실증된 경로다.
# ⚠️ 그래서 이 데이터소스는 credential 프록시 iptables 에 의존한다. 노드 재부팅으로
#    DNAT 규칙이 사라지면 CloudWatch 패널이 죽는다 — Loki S3 적재를 실패시킨 그 기전이다.
#
# ⚠️ 정책이 붙는 곳은 **공용 ECS Task Role** 이라 prod·dev API 태스크도 이 권한을 갖게 된다
#    (기존 monitoring-* 인라인 정책들과 같은 한계다). 읽기 전용 지표 조회라 수용한다.
#
# Resource 가 "*" 인 것은 선택이 아니다 — cloudwatch 의 지표 조회 액션들은
# 리소스 수준 권한을 지원하지 않는다.
resource "aws_iam_role_policy" "grafana_cloudwatch_read" {
  name = "${var.environment}-grafana-cloudwatch-read"
  role = split("/", var.task_role_arn)[1] # ARN 에서 역할 이름만 추출

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          # 데이터소스가 차원 값을 태그로 찾을 때 쓴다
          "tag:GetResources",
        ]
        Resource = "*"
      }
      # ec2:DescribeRegions 는 monitoring-prometheus-access 가 이미 준다 — 중복 부여하지 않는다
    ]
  })
}

resource "aws_iam_role_policy" "grafana_sns_publish" {
  count = var.sns_topic_arn_prod != "" || var.sns_topic_arn_dev != "" ? 1 : 0

  name = "${var.environment}-grafana-sns-publish"
  role = split("/", var.task_role_arn)[1] # ARN 에서 역할 이름만 추출

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = compact([var.sns_topic_arn_prod, var.sns_topic_arn_dev])
      }
    ]
  })
}
