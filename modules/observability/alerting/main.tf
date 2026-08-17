# 알림 전달 경로 (SNS → AWS Chatbot → Slack)
#
# 이 경로는 자체 호스팅 관측 스택(Prometheus/Grafana/Loki) 바깥에 있다.
# 모니터링 노드가 죽어도 알림은 도달해야 하므로 AWS 관리형 구성요소만 쓴다.
# 자세한 배경: docs/runbook/phase-01-alarm-backstop.md

# SNS 토픽 — 모든 CloudWatch 알람의 단일 진입점.
# 팬아웃 구조이므로 나중에 이메일·PagerDuty 등 구독을 추가해도 알람 쪽은 손대지 않는다.
resource "aws_sns_topic" "alerts" {
  name         = "${var.project_name}-alerts-${var.name_suffix}"
  display_name = "Groble ${var.name_suffix} Alerts"

  # KMS 암호화는 의도적으로 걸지 않았다.
  # CloudWatch 알람이 SNS로 발행하려면 고객 관리형 키에 별도 키 정책이 필요한데,
  # 알림 본문에 담기는 것은 지표명·임계치·상태뿐이라 비밀값이 아니다.

  tags = {
    Name = "${var.project_name}-alerts-${var.name_suffix}"
  }
}

# CloudWatch가 이 토픽에 발행할 수 있도록 허용
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# AWS Chatbot (현 Amazon Q Developer in chat applications)
#
# ⚠️ 선행 조건: Slack 워크스페이스를 AWS 콘솔에서 1회 OAuth 승인해야 한다.
#    이 승인은 Terraform으로 할 수 없다. 승인 후 얻는 workspace ID를
#    slack_workspace_id 변수에 넣으면 아래 리소스가 활성화된다.
#    승인 전에는 count = 0이라 apply가 실패하지 않는다.
#
# ⚠️ Chatbot 리소스는 반드시 aws.chatbot 별칭(us-east-2)으로 만든다.
#    ap-northeast-2에는 Chatbot API 엔드포인트 자체가 없다 (versions.tf 참조).
#    SNS 토픽은 ap-northeast-2에 그대로 두며, Chatbot은 교차 리전 토픽을 구독할 수 있다.
# ---------------------------------------------------------------------------

locals {
  chatbot_enabled = var.slack_workspace_id != "" && var.slack_channel_id != ""
}

resource "aws_iam_role" "chatbot" {
  count = local.chatbot_enabled ? 1 : 0

  name = "${var.project_name}-chatbot-${var.name_suffix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-chatbot-${var.name_suffix}-role"
  }
}

# 알람 메시지에 지표 그래프와 리소스 컨텍스트를 붙이기 위한 읽기 권한
resource "aws_iam_role_policy_attachment" "chatbot_readonly" {
  count = local.chatbot_enabled ? 1 : 0

  role       = aws_iam_role.chatbot[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "alerts" {
  count    = local.chatbot_enabled ? 1 : 0
  provider = aws.chatbot

  configuration_name = "${var.project_name}-alerts-${var.name_suffix}"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  sns_topic_arns     = [aws_sns_topic.alerts.arn]

  # 채널에서 실행 가능한 명령의 상한. 읽기 전용으로 묶어
  # Slack에서 인프라를 변경하는 일이 없게 한다.
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  logging_level = "ERROR"

  tags = {
    Name = "${var.project_name}-alerts-${var.name_suffix}"
  }
}
