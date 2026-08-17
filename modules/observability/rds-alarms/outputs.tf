output "alarm_names" {
  description = "생성된 RDS 알람 이름 목록"
  value = [
    aws_cloudwatch_metric_alarm.cpu_utilization.alarm_name,
    aws_cloudwatch_metric_alarm.cpu_credit_balance.alarm_name,
    aws_cloudwatch_metric_alarm.database_connections.alarm_name,
    aws_cloudwatch_metric_alarm.free_storage_space.alarm_name,
    aws_cloudwatch_metric_alarm.freeable_memory.alarm_name,
    aws_cloudwatch_metric_alarm.swap_usage.alarm_name,
  ]
}
