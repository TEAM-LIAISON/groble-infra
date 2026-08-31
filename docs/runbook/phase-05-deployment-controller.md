# Phase 5 — 배포 컨트롤러 전환 (CodeDeploy → ECS rolling)

> [← Phase 4](./phase-04-monitoring-node-rebuild.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 6 →](./phase-06-elasticache.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | Blue/Green은 4슬롯 플릿에서 여유가 0이라 유지할 수 없다(계획서 §2.6) |
| **사용자 영향** | 없음 — 신 서비스가 준비된 뒤 리스너를 스왑한다 |
| **선행 조건** | 계획서 §3 의 앱 측 4건(expand/contract · readiness/liveness · graceful shutdown · 드레이닝 값)이 모두 완료. **이것이 차단 조건이다** — 요청서 [`handoff/rolling-deploy-prerequisites.md`](../handoff/rolling-deploy-prerequisites.md) |
| **되돌리기** | **리스너 규칙 되돌리기** |

> ⚠️ `deployment_controller`는 변경 시 **리소스 재생성을 강제**한다. 그냥 apply하면 서비스가 destroy → create되어 태스크가 0이 되는 구간이 생긴다. 아래 절차는 그것을 피하기 위한 것이다.

---

## 절차

**현재 `api_desired_count = 1`인 상태에서 수행한다.** desired 를 올리지 않는다 —
증설은 노드가 2대가 되는 [Phase 7](./phase-07-prod-asg.md)(prod) · [Phase 8-b](./phase-08b-dev-cache-asg.md)(dev) 의 작업이다.

### ⚠️ desired = 1 구간에는 계획서의 To-Be 비율을 쓸 수 없다

ECS 는 두 값을 desired 에 곱한 뒤 **서로 다른 방향으로 정수화**한다 —
`minimumHealthyPercent` 는 **올림**, `maximumPercent` 는 **내림**이다.

| 설정 | 최소 유지 | 상한 | desired = 1 에서 |
|---|---|---|---|
| Prod To-Be `100 / 150` | ceil(1.0) = **1** | floor(1.5) = **1** | 상한이 1인데 1개를 내릴 수도 없다 → **배포 교착** |
| Dev To-Be `50 / 100` | ceil(0.5) = **1** | floor(1.0) = **1** | 동일 → **배포 교착** |
| **임시 `100 / 200`** | **1** | floor(2.0) = **2** | 신 1개 기동 → 구 1개 제거 ✅ |

계획서 §2.1 의 `100/150` · `50/100` 은 **desired 2 · 4슬롯 플릿을 전제로 계산된 값**이다.
그대로 쓰면 `update-service` 가 신규 태스크를 하나도 띄우지 못하고 배포가 멈춘다.

→ **이 Phase 에서는 임시로 `100 / 200` 을 쓰고, Phase 7/8 에서 desired 를 2로 올릴 때 To-Be 값으로 바꾼다.**
`deployment_minimum_healthy_percent` / `deployment_maximum_percent` 는 `deployment_controller` 와 달리
**in-place 변경**이라 서비스 재생성을 유발하지 않는다. 미루어도 안전하다.

### 슬롯 회계 (prod 노드 1대 = t3.medium, ENI 2슬롯)

| 구간 | 슬롯 | 비고 |
|---|---|---|
| 1~5 (구·신 병존) | 구 1 + 신 1 = **2/2** | **여유 0. 이 구간에는 양쪽 다 배포할 수 없다** — 짧게 유지할 것 |
| 6-a 이후 (구 desired 0) | 신 1 = **1/2** | 배포 피크(임시 200%) 2태스크가 여기 들어간다 |

배포 피크 2태스크의 메모리는 1,370×2 + Redis 128 + ECS 오버헤드 ~500 ≈ **3.37 GiB** 로
t3.medium 가용치(~3.75 GiB) 안이다. 배치 판단은 `memoryReservation = 500` 기준이라 막히지 않는다.

### 단계

1. **신 서비스 생성** — 기존 **Green 타깃그룹**에 rolling 방식 ECS 서비스 추가
   ```hcl
   deployment_controller { type = "ECS" }
   deployment_minimum_healthy_percent = 100
   deployment_maximum_percent         = 200   # 임시값 — Phase 7/8 에서 prod 150 / dev 100 으로
   deployment_circuit_breaker { enable = true, rollback = true }
   ```
   - 기존(CodeDeploy) 서비스는 **그대로 살려둔다**
2. 신 서비스의 태스크가 Green TG에서 **healthy**가 될 때까지 대기
3. **테스트 리스너(9443)로 신 서비스를 먼저 검증** — 이 리스너는 아직 존재하므로 마지막으로 활용한다
4. **ALB 리스너(443) 규칙을 Blue TG → Green TG로 스왑**
5. **관찰 기간** (최소 30분): 5xx, p99, 에러율 지표 확인
6. **`6-a` 와 `6-b` 를 반드시 나눠서 진행한다** (아래 참조)
   - **6-a.** 이상 없으면 구 서비스 **`desired_count = 0`** — 리소스는 남긴다
     → 슬롯이 1개 풀린다. **여기서 검증 항목의 rolling 배포 · 서킷 브레이커 확인을 수행한다**
   - **6-b.** 검증이 끝나면 구 서비스 **리소스 제거** ← *되돌릴 수 없어지는 지점*
7. CodeDeploy 애플리케이션·배포그룹·IAM 역할 제거 (Phase 11에서 일괄 정리해도 무방)
8. **CI 파이프라인 전환**: `appspec` 기반 CodeDeploy 호출 → 태스크 정의 등록 + `aws ecs update-service`
   - Terraform은 `lifecycle { ignore_changes = [task_definition] }` 유지

> **6번을 왜 쪼개는가.** 검증 항목은 "구 서비스 제거 **전에** rolling 배포 1회 성공"을 요구하는데,
> 구 서비스가 태스크를 들고 있는 동안에는 슬롯이 2/2로 꽉 차 **surge 배포 자체가 불가능**하다.
> 구 서비스를 `desired 0` 으로 내려 슬롯을 비우면 검증이 가능해지고, 리소스는 남아 있으므로
> 롤백 경로도 유지된다 — 다만 **초 단위에서 몇 분으로 열화**된다(아래 롤백 절 참조).

## 검증

- [ ] 리스너 스왑 후 트래픽이 신 서비스 태스크로 가는지 (TG별 `RequestCount`)
- [ ] CI에서 **rolling 배포를 1회 실제로 수행**해 정상 동작 확인 — **6-a 이후에 한다** (그 전에는 슬롯이 없다)
- [ ] 서킷 브레이커가 동작하는지 — 의도적으로 실패하는 이미지를 Dev에 배포해 롤백 확인
- [ ] `min/max` 가 **임시값 `100/200`** 인지, Phase 7/8 에서 To-Be 값으로 되돌릴 항목으로 인계되었는지
- [ ] 드레이닝 파라미터 정렬 (계획서 §3-3): `deregistration_delay` / `stopTimeout` / Spring graceful 값 확정 및 적용

## 롤백

**리스너 규칙을 Blue TG로 되돌린다.** 구 서비스가 그대로 살아 있으므로 즉시 복구된다.
이 마이그레이션에서 가장 깔끔한 되돌리기 지점이다.

**단, 6-a 를 지나면 롤백 품질이 한 단계 떨어진다.**

| 시점 | 롤백 방법 | 소요 |
|---|---|---|
| 1~5 (구 서비스 desired 1) | 리스너 규칙만 되돌린다 | **초 단위** |
| 6-a 이후 (구 서비스 desired 0) | 구 서비스 `desired 1` 복구 → healthy 대기 → 리스너 되돌리기 | **몇 분** |
| 6-b 이후 (구 서비스 제거) | ❌ 없다 | — |

> 되돌릴 수 없게 되는 시점: **6-b, 구 CodeDeploy 서비스 리소스 제거**.
> 그 전에 rolling 배포 1회 이상 성공과 서킷 브레이커 동작을 확인한다(6-a 구간에서 수행).

---

[← Phase 4 — 모니터링 노드 재구축](./phase-04-monitoring-node-rebuild.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 6 — Prod Redis → ElastiCache →](./phase-06-elasticache.md)
