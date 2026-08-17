# ALB / 타깃그룹 CloudWatch 알람
#
# 설계 원칙 두 가지:
#
# 1. **서비스 단위로 알람을 만들고, 서비스별로 다른 채널에 보낸다.**
#    prod 장애와 dev 장애는 대응 긴급도가 달라 같은 채널에 섞으면 안 된다.
#
# 2. **한 서비스의 타깃그룹들을 집계해 판정한다.**
#    Blue/Green은 배포마다 활성 TG가 뒤바뀐다. 특정 TG에 알람을 고정하면
#    스왑 직후부터 유휴 TG를 감시하게 되어 무의미해진다.
#    Phase 4에서 단일 TG로 정리되면 이 구조는 자연히 단순해진다.
#
# 임계치는 기준선 데이터가 없어 "명백한 이상만 잡는" 수준으로 넉넉하게 잡았다.
# 1주일 기준선 수집 후 조인다. docs/runbook/phase-01-alarm-backstop.md 4번 참조.

locals {
  common_tags = {
    Phase = "phase-1-alarm-backstop"
  }

  # 5xx·지연 알람을 만들 서비스만 추린다
  traffic_services = { for k, v in var.services : k => v if v.traffic_alarms }
}

# ---------------------------------------------------------------------------
# ALB 전체 (서비스별 분리 불가)
# ---------------------------------------------------------------------------

# ALB 자신이 생성한 5xx — 타깃에 도달조차 못한 경우(정상 타깃 없음, 연결 실패 등).
# 앱 버그보다 인프라 이상을 가리키므로 Target 5xx보다 임계치를 낮게 둔다.
#
# ⚠️ 이 지표는 TargetGroup 차원이 없어 prod·dev·monitoring 트래픽이 합산된다.
#    울렸을 때 어느 서비스인지는 서비스별 알람과 타깃 헬스를 함께 봐야 한다.
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name        = "${var.project_name}-alb-elb-5xx"
  alarm_description = "ALB가 직접 5xx를 반환하고 있다 (타깃 미도달·연결 실패). 이 지표는 prod/dev 합산이므로, 어느 서비스인지는 서비스별 타깃 헬스 알람을 함께 확인할 것."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.elb_5xx_threshold
  period              = 300
  evaluation_periods  = 1

  # 요청이 없으면 데이터도 없다. 무데이터는 정상으로 간주한다.
  treat_missing_data = "notBreaching"

  alarm_actions = var.elb_level_alarm_actions
  ok_actions    = var.elb_level_ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb-elb-5xx" })
}

# ---------------------------------------------------------------------------
# 서비스별 트래픽 품질
# ---------------------------------------------------------------------------

# 애플리케이션이 반환한 5xx. 서비스의 타깃그룹들을 합산한다.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = local.traffic_services

  alarm_name        = "${var.project_name}-${each.key}-target-5xx"
  alarm_description = "${each.key} 애플리케이션이 5xx를 반환하고 있다. 앱 로그(Loki)와 최근 배포를 확인할 것."

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.target_5xx_threshold
  evaluation_periods  = 1

  treat_missing_data = "notBreaching"

  metric_query {
    id          = "total_5xx"
    expression  = "SUM(METRICS())"
    label       = "${each.key} 5xx 합계"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = each.value.target_groups
    content {
      id          = "m${metric_query.key}"
      return_data = false

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = "HTTPCode_Target_5XX_Count"
        stat        = "Sum"
        period      = 300

        dimensions = {
          LoadBalancer = var.alb_arn_suffix
          TargetGroup  = metric_query.value
        }
      }
    }
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${each.key}-target-5xx" })
}

# p99 응답 지연.
# 백분위수는 평균 낼 수 없으므로 SUM이 아니라 MAX로 집계한다.
# 유휴 TG는 트래픽이 없어 데이터를 내지 않고, MAX는 무데이터를 무시하므로
# 결과적으로 활성 TG의 p99가 그대로 나온다.
# 일시적 스파이크로 울리지 않도록 3회 연속(15분) 초과해야 발동한다.
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  for_each = local.traffic_services

  alarm_name        = "${var.project_name}-${each.key}-latency-p99"
  alarm_description = "${each.key} p99 응답시간이 15분간 임계치를 초과했다. DB 지연·GC·리소스 포화를 확인할 것."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p99_threshold_seconds
  evaluation_periods  = 3
  datapoints_to_alarm = 3

  treat_missing_data = "notBreaching"

  metric_query {
    id          = "max_p99"
    expression  = "MAX(METRICS())"
    label       = "${each.key} p99 (활성 TG)"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = each.value.target_groups
    content {
      id          = "m${metric_query.key}"
      return_data = false

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = "TargetResponseTime"
        stat        = "p99"
        period      = 300

        dimensions = {
          LoadBalancer = var.alb_arn_suffix
          TargetGroup  = metric_query.value
        }
      }
    }
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${each.key}-latency-p99" })
}

# ---------------------------------------------------------------------------
# 서비스별 타깃 헬스 (트래픽 여부와 무관하게 항상 감시)
# ---------------------------------------------------------------------------

# 정상 타깃 합이 0 = 해당 서비스가 트래픽을 처리하지 못하는 상태
resource "aws_cloudwatch_metric_alarm" "no_healthy_host" {
  for_each = var.services

  alarm_name        = "${var.project_name}-${each.key}-no-healthy-host"
  alarm_description = "${each.key} 서비스에 정상 타깃이 없다. ECS 서비스 상태와 태스크 배치 실패(RESOURCE:ENI 포함)를 확인할 것."

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 5
  datapoints_to_alarm = 5

  # 지표가 사라지는 것 자체가 이상 신호다.
  treat_missing_data = "breaching"

  metric_query {
    id          = "healthy_total"
    expression  = "SUM(METRICS())"
    label       = "${each.key} 정상 타깃 합계"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = each.value.target_groups
    content {
      id          = "m${metric_query.key}"
      return_data = false

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = "HealthyHostCount"
        stat        = "Minimum"
        period      = 60

        dimensions = {
          LoadBalancer = var.alb_arn_suffix
          TargetGroup  = metric_query.value
        }
      }
    }
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${each.key}-no-healthy-host" })
}

# 이관 절차의 중단(Abort) 기준 — "UnHealthyHostCount > 0이 5분 이상 지속".
# 위 알람과 달리 "타깃은 있으나 헬스체크에 실패하는" 상태를 구분해 잡는다.
# 5분 지속 조건은 배포 중 신 태스크가 기동하는 구간(JVM 부팅 ~2분)에서
# 오탐이 나지 않게 하는 여유이기도 하다.
resource "aws_cloudwatch_metric_alarm" "unhealthy_host" {
  for_each = var.services

  alarm_name        = "${var.project_name}-${each.key}-unhealthy-host"
  alarm_description = "${each.key} 서비스에 헬스체크 실패 타깃이 5분 이상 존재한다. 이관 절차의 중단 기준에 해당한다."

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 5
  datapoints_to_alarm = 5

  treat_missing_data = "notBreaching"

  metric_query {
    id          = "unhealthy_total"
    expression  = "SUM(METRICS())"
    label       = "${each.key} 비정상 타깃 합계"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = each.value.target_groups
    content {
      id          = "m${metric_query.key}"
      return_data = false

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = "UnHealthyHostCount"
        stat        = "Maximum"
        period      = 60

        dimensions = {
          LoadBalancer = var.alb_arn_suffix
          TargetGroup  = metric_query.value
        }
      }
    }
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${each.key}-unhealthy-host" })
}
