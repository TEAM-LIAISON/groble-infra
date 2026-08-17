variable "project_name" {
  description = "프로젝트 이름 (리소스 이름 접두사)"
  type        = string
}

variable "environment" {
  description = "환경 이름 (prod / dev)"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS 인스턴스 식별자 (CloudWatch DBInstanceIdentifier 차원)"
  type        = string
}

variable "alarm_actions" {
  description = "ALARM 상태 진입 시 통지할 SNS 토픽 ARN 목록"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "OK 상태 복귀 시 통지할 SNS 토픽 ARN 목록"
  type        = list(string)
  default     = []
}

# --- 임계치 ---------------------------------------------------------------
# db.t3.micro 기준 잠정값. 1주 기준선 수집 후 조인다.

variable "cpu_threshold_percent" {
  description = "CPU 사용률 임계치(%). 15분 연속 초과 시 발동"
  type        = number
  default     = 80
}

variable "cpu_credit_threshold" {
  description = <<-EOT
    버스트 크레딧 잔량 임계치. t3.micro는 시간당 12크레딧을 벌고 최대 288까지 쌓인다.
    30이면 baseline 초과 사용을 약 2.5시간 더 버틸 수 있는 시점이다 — 대응할 여유가 있다.
  EOT
  type        = number
  default     = 30
}

variable "connections_threshold" {
  description = <<-EOT
    커넥션 수 임계치.

    ⚠️ 이 인스턴스의 `max_connections`는 파라미터 그룹에서 **200으로 명시 설정**되어 있다
    (엔진 기본 공식값 약 85가 아니다). 그러나 실질 상한은 커넥션 수가 아니라 **메모리**다 —
    여유 메모리가 평소 40MiB뿐이어서 커넥션이 늘면 그쪽이 먼저 터진다.
    따라서 60은 "max_connections의 30%"가 아니라 "메모리가 감당할 수 있는 대략의 상한"으로 잡은 값이다.
    실측 사용량은 14개다.
  EOT
  type        = number
  default     = 60
}

variable "free_storage_threshold_bytes" {
  description = "여유 스토리지 임계치(바이트). 기본 4GiB — 현재 할당 20GB의 20%"
  type        = number
  default     = 4294967296
}

variable "freeable_memory_threshold_bytes" {
  description = <<-EOT
    여유 메모리 임계치(바이트). 기본 15MiB.

    ⚠️ 이 값은 "건강한 수준"이 아니라 **"평소보다 나빠졌음"의 기준**이다.
    이 인스턴스의 여유 메모리는 24시간 실측 21~62MiB(평균 42MiB)로, 만성적으로 부족한 상태다
    (버퍼 풀이 `{DBInstanceClassMemory*3/4}` ≈ 768MiB를 점유). 처음 100MiB로 잡았더니
    정상 상태가 이미 그 아래여서 알람이 영구히 켜져 있었다 — 정보량이 0인 알람이다.

    관측 최소치(21MiB) 아래로 내려 **더 악화될 때만** 울리게 했다.
    만성 부족 자체는 `swap_usage` 알람과 infra-future-improvements.md의 기록으로 추적한다.
  EOT
  type        = number
  default     = 15728640
}

variable "swap_usage_threshold_bytes" {
  description = <<-EOT
    스왑 사용량 임계치(바이트). 기본 600MiB.

    메모리 부족이 **실제로 해를 끼치고 있는지**는 여유 메모리보다 이 지표가 직접 신호다.
    RDS의 스왑은 곧 디스크 I/O이고, gp2 볼륨이라 지연으로 직결된다.

    7일 실측은 400~482MiB 대역의 **안정된 고원**이다(증가 추세 아님).
    600MiB는 그 진동 폭 위로, 정상 변동에는 반응하지 않고 실제 악화만 잡는다.
    이 알람이 울린다면 버퍼 풀 축소 또는 인스턴스 클래스 상향 결정을 미룰 수 없다는 뜻이다.
  EOT
  type        = number
  default     = 629145600
}
