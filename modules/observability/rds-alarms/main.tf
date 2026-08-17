# RDS MySQL CloudWatch 알람
#
# 임계치는 db.t3.micro(vCPU 2 버스터블 / 메모리 1GiB / 20GB→100GB 오토스케일)를
# 전제로 잡았다. 인스턴스 클래스를 올리면 재검토할 것.
# docs/runbook/phase-01-alarm-backstop.md 참조.

locals {
  common_tags = {
    Phase = "phase-1-alarm-backstop"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-cpu"
  alarm_description = "RDS CPU 사용률이 15분간 높게 유지되고 있다. 슬로우 쿼리와 커넥션 수를 확인할 것."

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_threshold_percent
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-cpu" })
}

# ⚠️ 런북 최소 세트에 없던 항목이지만 t3 계열에서는 CPUUtilization보다 중요할 수 있다.
# 버스트 크레딧이 소진되면 CPU가 baseline(10%)으로 강제 제한되어
# 사용률 지표는 낮은데 응답은 급격히 느려지는, 진단하기 까다로운 상태가 된다.
resource "aws_cloudwatch_metric_alarm" "cpu_credit_balance" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-cpu-credits"
  alarm_description = "RDS 버스트 크레딧이 소진되어 간다. 곧 CPU가 baseline으로 제한되어 전반적으로 느려진다."

  namespace   = "AWS/RDS"
  metric_name = "CPUCreditBalance"
  statistic   = "Minimum"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "LessThanThreshold"
  threshold           = var.cpu_credit_threshold
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-cpu-credits" })
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-connections"
  alarm_description = "RDS 커넥션 수가 상한에 근접했다. 커넥션 풀 설정과 누수를 확인할 것."

  namespace   = "AWS/RDS"
  metric_name = "DatabaseConnections"
  statistic   = "Maximum"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.connections_threshold
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-connections" })
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-storage"
  alarm_description = "RDS 여유 스토리지가 부족하다. 오토스케일이 동작하는지, 상한(100GB)에 닿았는지 확인할 것."

  namespace   = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  statistic   = "Minimum"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "LessThanThreshold"
  threshold           = var.free_storage_threshold_bytes
  period              = 300
  evaluation_periods  = 1

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-storage" })
}

# ⚠️ 런북 최소 세트 밖의 추가 항목.
#
# 이 인스턴스는 여유 메모리가 만성적으로 부족하다 (실측 21~62MiB / 총 1GiB).
# 따라서 이 알람의 임계치는 "건강한 수준"이 아니라 **"평소보다 나빠졌음"**의 기준이다.
# 만성 부족 자체는 아래 swap_usage 알람으로 추적한다. variables.tf의 상세 주석 참조.
resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-memory"
  alarm_description = "RDS 여유 메모리가 평소 수준(21~62MiB)보다 더 떨어졌다. 커넥션 급증이나 쿼리 패턴 변화를 확인할 것."

  namespace   = "AWS/RDS"
  metric_name = "FreeableMemory"
  statistic   = "Minimum"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "LessThanThreshold"
  threshold           = var.freeable_memory_threshold_bytes
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-memory" })
}

# ⚠️ 런북 최소 세트 밖의 추가 항목.
#
# 메모리 부족이 실제로 해를 끼치고 있는지는 FreeableMemory보다 이 지표가 직접 신호다.
# RDS의 스왑은 곧 디스크 I/O이고 gp2 볼륨이라 지연으로 직결된다.
# 이 알람이 울리면 버퍼 풀 축소 또는 인스턴스 클래스 상향 결정을 미룰 수 없다.
resource "aws_cloudwatch_metric_alarm" "swap_usage" {
  alarm_name        = "${var.project_name}-${var.environment}-rds-swap"
  alarm_description = "RDS 스왑 사용량이 평소 고원(400~482MiB)을 넘어 증가했다. 메모리 압박이 악화되고 있다 — 버퍼 풀 축소 또는 인스턴스 상향을 검토할 것."

  namespace   = "AWS/RDS"
  metric_name = "SwapUsage"
  statistic   = "Maximum"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.swap_usage_threshold_bytes
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3

  treat_missing_data = "missing"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-rds-swap" })
}
