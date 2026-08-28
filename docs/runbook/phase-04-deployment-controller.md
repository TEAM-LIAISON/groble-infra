# Phase 4 — 배포 컨트롤러 전환 (CodeDeploy → ECS rolling)

> [← Phase 3](./phase-03-nat-gateway.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 5 →](./phase-05-monitoring-node-rebuild.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | Blue/Green은 4슬롯 플릿에서 여유가 0이라 유지할 수 없다(계획서 §2.6) |
| **사용자 영향** | 없음 — 신 서비스가 준비된 뒤 리스너를 스왑한다 |
| **선행 조건** | 계획서 §4 To-Do 1번(expand/contract 팀 합의) 완료. **이것이 차단 조건이다** |
| **되돌리기** | **리스너 규칙 되돌리기** |

> ⚠️ `deployment_controller`는 변경 시 **리소스 재생성을 강제**한다. 그냥 apply하면 서비스가 destroy → create되어 태스크가 0이 되는 구간이 생긴다. 아래 절차는 그것을 피하기 위한 것이다.

---

## 절차

**현재 `api_desired_count = 1`인 상태에서 수행한다** (슬롯 2개만 사용 → 여유 확보).

1. **신 서비스 생성** — 기존 **Green 타깃그룹**에 rolling 방식 ECS 서비스 추가
   ```hcl
   deployment_controller { type = "ECS" }
   deployment_minimum_healthy_percent = 100
   deployment_maximum_percent         = 150
   deployment_circuit_breaker { enable = true, rollback = true }
   ```
   - 기존(CodeDeploy) 서비스는 **그대로 살려둔다**
2. 신 서비스의 태스크가 Green TG에서 **healthy**가 될 때까지 대기
3. **테스트 리스너(9443)로 신 서비스를 먼저 검증** — 이 리스너는 아직 존재하므로 마지막으로 활용한다
4. **ALB 리스너(443) 규칙을 Blue TG → Green TG로 스왑**
5. **관찰 기간** (최소 30분): 5xx, p99, 에러율 지표 확인
6. 이상 없으면 구 서비스 `desired_count = 0` → 리소스 제거
7. CodeDeploy 애플리케이션·배포그룹·IAM 역할 제거 (Phase 11에서 일괄 정리해도 무방)
8. **CI 파이프라인 전환**: `appspec` 기반 CodeDeploy 호출 → 태스크 정의 등록 + `aws ecs update-service`
   - Terraform은 `lifecycle { ignore_changes = [task_definition] }` 유지

## 검증

- [ ] 리스너 스왑 후 트래픽이 신 서비스 태스크로 가는지 (TG별 `RequestCount`)
- [ ] CI에서 **rolling 배포를 1회 실제로 수행**해 정상 동작 확인
- [ ] 서킷 브레이커가 동작하는지 — 의도적으로 실패하는 이미지를 Dev에 배포해 롤백 확인
- [ ] 드레이닝 파라미터 정렬 (계획서 §3-3): `deregistration_delay` / `stopTimeout` / Spring graceful 값 확정 및 적용

## 롤백

**리스너 규칙을 Blue TG로 되돌린다.** 구 서비스가 그대로 살아 있으므로 즉시 복구된다.
이 마이그레이션에서 가장 깔끔한 되돌리기 지점이다.

> 되돌릴 수 없게 되는 시점: **구 CodeDeploy 서비스 제거**. 그 전에 rolling 배포 1회 이상 성공과 서킷 브레이커 동작을 확인한다.

---

[← Phase 3 — NAT Gateway 전환](./phase-03-nat-gateway.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 5 — 모니터링 노드 재구축 →](./phase-05-monitoring-node-rebuild.md)
