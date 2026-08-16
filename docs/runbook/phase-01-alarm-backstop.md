# Phase 1 — 알람 백스톱 확보

> [← Phase 0](./phase-00-terraform-state-s3.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 2 →](./phase-02-observability.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | 이후 단계에서 문제가 생겼을 때 **자체 호스팅 관측이 죽어도 알림이 도달**해야 한다. Phase 4의 서킷 브레이커도 이 알람에 의존한다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 리소스 삭제 |

> Phase 0에서 미확인으로 남은 **state 객체의 CloudTrail 데이터 이벤트 기록 여부**를 이 Phase 착수 시 함께 재확인한다.

---

## 절차

1. SNS 토픽 생성 + 외부 채널 구독 (Slack webhook / 이메일)
2. CloudWatch 알람 생성 — 최소 세트:
   - ALB `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`
   - TargetGroup `UnHealthyHostCount` (Prod Blue/Green TG)
   - ALB `TargetResponseTime` p99
   - RDS `CPUUtilization`, `DatabaseConnections`, `FreeStorageSpace`
3. 임계치는 **현재 기준선을 1주일 관측한 뒤** 확정 (초기에는 넉넉하게)
4. **같은 1주 동안 트래픽 기준선을 함께 기록한다** (계획서 §4 To-Do 9) — 알람 임계치와 별개로, 용량 결정의 근거 데이터가 지금 없다:
   - ALB `RequestCountPerTarget`(합계·피크), `TargetResponseTime` p50/p99
   - 피크 시간대와 **피크/평균 비율**
   - Prod API 태스크 CPU/메모리 사용률 (cAdvisor)
   - 결과를 계획서 §2.1 옆에 표로 남긴다. desired 2가 충분한지, 동적 스케일링(향후 개선 Low-3) 트리거에 얼마나 가까운지가 이 표로 판단된다

## 검증

- [ ] 알람을 수동으로 `ALARM` 상태로 전환해 **외부 채널까지 실제로 도달**하는지 확인
- [ ] 알람이 `INSUFFICIENT_DATA`로 방치되지 않는지
- [ ] 트래픽 기준선 표가 작성되었는지

## 롤백

리소스 삭제. 다른 단계에 영향 없음.

---

[← Phase 0 — Terraform state를 S3로 이전](./phase-00-terraform-state-s3.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 2 — 관측 선행 전환 →](./phase-02-observability.md)
