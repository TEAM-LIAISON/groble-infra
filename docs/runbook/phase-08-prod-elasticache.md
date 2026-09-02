# Phase 8 — Prod Redis → ElastiCache ⚠️

> [← Phase 7](./phase-07-dev-cache-asg.md) · [이관 절차 목차](README.md) · [다음: Phase 9 →](./phase-09-prod-asg.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | host-mode 싱글턴 컨테이너는 cattle 노드에서 유지할 수 없다. [9](./phase-09-prod-asg.md)(구 노드 드레인)의 **선행 조건**이다 |
| **선행 조건** | [Phase 6](./phase-06-deployment-controller.md)(rolling) · **[7](./phase-07-dev-cache-asg.md)-A(Dev ElastiCache) 완료** — 같은 전환을 Dev 에서 먼저 해본다 |
| **사용자 영향** | **진행 중이던 체크아웃 세션·재고 예약·멱등성 키가 전부 소실된다** |
| **시점** | **저트래픽 시간대 필수.** TTL이 30분이므로 최소 30분의 안정화 창을 확보한다 |
| **되돌리기** | 되돌려도 재소실 |

> 이 Phase는 **되돌려도 손실이 반복된다**(되돌리는 순간 다시 상태가 바뀐다). 전후로 결제 지표를 주의 깊게 본다.

---

## Dev 에서 이미 해본 것 / 여기서 처음인 것

[7](./phase-07-dev-cache-asg.md)-A 가 같은 전환을 Dev 에서 먼저 수행한다.
**착수 전에 그 문서의 "인계할 것" 체크리스트가 채워져 있어야 한다.**

| | Dev([7](./phase-07-dev-cache-asg.md)-A)에서 검증됨 | **여기서 처음** |
|---|---|---|
| `replication_group` 리소스 정의 · SG · 유지보수 창 | ✅ | |
| 앱의 ElastiCache 연결 · 엔드포인트 전환 | ✅ | |
| **stop-first 시퀀스** | ❌ (dev 엔 지킬 결제 상태가 없어 rolling 으로 했다) | **⚠️ 여기서 처음** |
| **결제 상태 소실 · 실트래픽 순단** | ❌ | **⚠️ 여기서 처음** |

**따라서 Dev 리허설이 이 Phase 의 위험을 다 없애지는 않는다.** 아래 3번의 stop-first 절차는
어디서도 예행되지 않았으므로 명령을 미리 적어두고 순서대로 실행한다.

---

## 절차

1. **ElastiCache 생성** — `cache.t4g.micro`, **2c**, 단일 노드
   - Terraform 리소스는 **`aws_elasticache_replication_group`** (`num_cache_clusters = 1`, `automatic_failover_enabled = false`) — `aws_elasticache_cluster`가 아님. replica 추가가 온라인 변경이 되게 하기 위함 (계획서 §2.3)
   - 앱은 `primary_endpoint_address`를 바라본다
   - **유지보수 창을 트래픽 최저 시간대로 명시 지정** (기본값은 무작위)
   - **자동 스냅샷 활성화**
   - SG: API 태스크 SG로부터 6379 허용
2. 저트래픽 시간대 진입, **결제 지표 기준선 기록**
3. **stop-first 전환** — rolling이 아니다 ⚠️
   - 이유: surge rolling(`100/150`)으로 배포하면 구 태스크(컨테이너 Redis)와 신 태스크(ElastiCache)가 몇 분간 **동시에 실트래픽**을 받아 멱등성 키·재고 카운터가 두 저장소로 갈라진다(split-brain). 중복 결제 방어가 실제로 뚫리는 창이다 (계획서 §2.3).
   - 절차:
     ```bash
     # (a) 일시적으로 stop-first로 전환
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --deployment-configuration minimumHealthyPercent=0,maximumPercent=100
     # (b) REDIS_HOST를 ElastiCache 엔드포인트로 바꾼 태스크 정의로 배포
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --task-definition <new-revision>
     # (c) 신 태스크 healthy 확인 후 원래 값으로 복구
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --deployment-configuration minimumHealthyPercent=100,maximumPercent=150
     ```
   - 예상 순단: 구 태스크 종료 → 신 태스크 healthy까지 **1~2분** (JVM 기동 + 헬스체크). 저트래픽 창에서 수용한다.
   - Terraform 서비스 리소스에 `deployment_minimum_healthy_percent`가 선언되어 있으면 (c) 후 `terraform plan`이 no changes인지 확인한다.
4. **30분 안정화 관찰** — 결제 성공률, 5xx, 재고 관련 오류
5. 구 Redis ECS 서비스 제거

## 검증

- [ ] ElastiCache에 키가 쌓이는지 (`checkout:*`, `stock:reserved:*`, `user:cache:*`)
- [ ] 결제 플로우 E2E 1회 수동 확인
- [ ] 결제 성공률이 기준선 대비 유지되는지 (최소 1시간)
- [ ] 재고 예약/해제 정상 동작

## 롤백

`REDIS_HOST`를 구 컨테이너 IP로 되돌리고 **동일하게 stop-first로** 재배포. **다시 한 번 상태가 소실된다.**

> 되돌릴 수 없게 되는 시점: **ElastiCache로 전환한 순간.** 그 전에 저트래픽 시간대인지, 결제 지표 기준선을 기록했는지 확인한다.

## 남는 리스크

단일 노드이므로 **유지보수·장애 시 결제 상태 유실 창이 남는다.** replica 전환은 [`infra-future-improvements.md`](../plan/infra-future-improvements.md)의 **Urgent #1**이다.

---

[← Phase 7 — Dev ElastiCache + ASG 전환](./phase-07-dev-cache-asg.md) · [이관 절차 목차](README.md) · [다음: Phase 9 — Prod ASG 전환 →](./phase-09-prod-asg.md)
