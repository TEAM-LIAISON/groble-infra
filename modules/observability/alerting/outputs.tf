output "sns_topic_arn" {
  description = "알람이 발행할 SNS 토픽 ARN"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "SNS 토픽 이름"
  value       = aws_sns_topic.alerts.name
}

output "chatbot_enabled" {
  description = "Slack ID가 주입되어 Chatbot 설정이 생성되었는지"
  value       = local.chatbot_enabled
}
