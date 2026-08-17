variable "project_name" {
  description = "프로젝트 이름 (리소스 이름 접두사)"
  type        = string
}

variable "name_suffix" {
  description = <<-EOT
    채널 구분자 (예: prod / dev). 토픽·Chatbot 설정·IAM 역할 이름에 붙는다.
    이 모듈을 채널마다 한 번씩 호출해 알림 경로를 분리한다 —
    긴급도가 다른 알림이 같은 채널에 섞이지 않게 하는 것이 목적이다.
  EOT
  type        = string
}

variable "aws_account_id" {
  description = "AWS 계정 ID (SNS 토픽 정책의 SourceAccount 조건)"
  type        = string
}

variable "slack_workspace_id" {
  description = <<-EOT
    AWS 콘솔에서 Slack 워크스페이스를 승인한 뒤 얻는 ID (T로 시작).
    빈 문자열이면 Chatbot 리소스를 만들지 않는다 — 승인 전에도 apply가 가능하다.
  EOT
  type        = string
  default     = ""
}

variable "slack_channel_id" {
  description = <<-EOT
    알림을 받을 Slack 채널 ID (C로 시작). 채널 이름이 아니다.
    Slack에서 채널 세부정보 하단에 표시된다.
  EOT
  type        = string
  default     = ""
}
