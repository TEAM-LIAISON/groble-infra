variable "project_name" {
  description = "프로젝트 이름 (리소스 이름 접두사)"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB의 ARN suffix (예: app/groble-load-balancer/e4cdf640...). 전체 ARN이 아니다 — CloudWatch 차원 값 형식"
  type        = string
}

variable "services" {
  description = <<-EOT
    ALB 뒤의 서비스별 알람 설정.

    - key: 알람 이름에 쓰인다 (prod / dev / monitoring)
    - target_groups: 그 서비스의 타깃그룹 ARN suffix 목록.
      Blue/Green이면 둘 다 넣는다. 알람은 목록을 집계해 판정하므로
      배포로 활성 TG가 뒤바뀌어도 영향받지 않는다.
    - alarm_actions / ok_actions: 이 서비스의 알림이 갈 SNS 토픽.
      서비스마다 다른 채널로 보낼 수 있다.
    - traffic_alarms: 5xx·지연 알람을 만들지 여부.
      사용자 트래픽을 받지 않는 서비스(모니터링 대시보드 등)는 false로 둬
      불필요한 알람과 비용을 줄인다. 타깃 헬스 알람은 항상 만든다.
  EOT
  type = map(object({
    target_groups  = list(string)
    alarm_actions  = list(string)
    ok_actions     = optional(list(string), [])
    traffic_alarms = optional(bool, true)
  }))
  default = {}
}

variable "elb_level_alarm_actions" {
  description = <<-EOT
    ALB 전체 5xx 알람의 통지 대상.

    ⚠️ HTTPCode_ELB_5XX_Count는 AWS가 TargetGroup 차원으로 발행하지 않는다
    (LoadBalancer / AvailabilityZone 뿐). 따라서 이 알람만은 prod·dev를 분리할 수 없어
    가장 심각도가 높은 채널로 보낸다.
  EOT
  type        = list(string)
  default     = []
}

variable "elb_level_ok_actions" {
  description = "ALB 전체 5xx 알람의 복구 통지 대상"
  type        = list(string)
  default     = []
}

# --- 임계치 ---------------------------------------------------------------
# 기준선 수집(1주) 전의 잠정값이다. 오탐으로 알람을 무시하게 되는 것이
# 미탐보다 나쁘므로, 초기값은 명백한 이상만 잡도록 넉넉하게 잡았다.

variable "elb_5xx_threshold" {
  description = "5분간 ALB 자체 5xx 건수 임계치"
  type        = number
  default     = 10
}

variable "target_5xx_threshold" {
  description = "5분간 애플리케이션 5xx 건수 임계치 (서비스별)"
  type        = number
  default     = 25
}

variable "latency_p99_threshold_seconds" {
  description = "p99 응답시간 임계치(초). 15분 연속 초과 시 발동"
  type        = number
  default     = 5
}
