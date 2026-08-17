output "alarm_names" {
  description = "생성된 ALB 관련 알람 이름 목록 (Phase 4의 ECS deployment alarms에서 참조한다)"
  value = concat(
    [aws_cloudwatch_metric_alarm.elb_5xx.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.target_5xx : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.latency_p99 : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.latency_p99_spike : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.no_healthy_host : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.unhealthy_host : a.alarm_name],
  )
}

output "target_5xx_alarm_names" {
  description = "서비스별 애플리케이션 5xx 알람 이름 — Phase 4 배포 자동 롤백 트리거 후보"
  value       = { for k, a in aws_cloudwatch_metric_alarm.target_5xx : k => a.alarm_name }
}
