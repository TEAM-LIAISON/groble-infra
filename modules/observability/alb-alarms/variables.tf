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
  description = <<-EOT
    5분간 애플리케이션 5xx 건수 임계치 (서비스별).

    실측(2026-08-10~16, prod): 5분 구간당 최대 **2건**, 7일 합계 5건.
    10은 평상시 최대의 5배로, 노이즈는 무시하고 실제 이상만 잡는다.
  EOT
  type        = number
  default     = 10
}

variable "latency_p99_threshold_seconds" {
  description = <<-EOT
    **지속적 성능 저하**를 잡는 p99 임계치(초). 15분 연속 초과 시 발동.

    실측(prod): 평상시 p99는 0.24~0.42초, p50은 0.05초. 2초는 평상시의 5배 이상이다.
    단발 스파이크는 이 알람이 아니라 `latency_p99_spike_threshold_seconds`가 담당한다.
  EOT
  type        = number
  default     = 2
}

variable "latency_p99_spike_threshold_seconds" {
  description = <<-EOT
    **단발 급증**을 잡는 p99 임계치(초). 5분 구간 1회만 초과해도 발동.

    지속 알람과 분리한 이유: 실측된 심각한 지연은 전부 단발이었다.
    2026-08-13에 p99가 13:45에 **42.3초**, 19:50에 **6.5초**를 기록했으나
    모두 단일 5분 구간이어서 "15분 연속" 조건으로는 임계치를 2초로 낮춰도 잡히지 않는다.
    42초 p99는 일부 사용자가 42초를 기다렸다는 뜻이므로 놓칠 수 없다.

    5초로 두면 위 두 사건이 잡히고, 7일간 그 외 오탐은 없다(2~3초대는 무시).
  EOT
  type        = number
  default     = 5
}
