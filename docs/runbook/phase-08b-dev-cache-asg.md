# Phase 8-b — Dev ElastiCache + ASG 전환

> [← Phase 8-a](./phase-08a-dev-rds.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 →](./phase-09-access-path.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | Dev 를 Prod 와 같은 형태로 만들어 §3-5 의 promote 게이트가 실제로 의미를 갖게 한다 |
| **선행 조건** | **[8-a](./phase-08a-dev-rds.md)**(노드 메모리 확보) · **[Phase 5](./phase-05-deployment-controller.md)**(rolling) · **[Phase 7](./phase-07-prod-asg.md)**(ASG 절차) |
| **사용자 영향** | Dev 만. 개발 작업이 없는 시간대 권장 |
| **되돌리기** | 단계별 |
| **비용** | **+$15/월** (ElastiCache `cache.t4g.micro`). 컴퓨트는 t3.medium → t3.small ×2 로 상쇄 |

> 원래 Phase 8 의 3·6·7 단계다. RDS 이관([8-a](./phase-08a-dev-rds.md))은 선행 조건이 없어 분리했다.

---

## 🔴 착수 전에 다시 재야 하는 값 — 계획서의 `memory = 900` 은 근거가 무너졌다

계획서 §2.1 이 확정한 dev 태스크 예산과, **2026-08-31 실측**이 어긋난다.

| | 계획서 §2.1 | 2026-08-31 실측 (14일) |
|---|---|---|
| `memoryReservation` | **800** | — |
| `memory` (하드리밋) | **900** | — |
| dev API working set max | — | **838.1 MiB** |
| dev API RSS max / p99 | — | **833.8 / 833.8 MiB** |
| dev API usage max (page cache 포함) | — | 841.3 MiB |
| 현재 하드리밋 | — | 1,500 MiB |
| (참고) prod API RSS max | — | 1,078.6 MiB |

**두 값 다 그대로 쓰면 안 된다.**
- `memoryReservation = 800` < 실사용 **834** → ECS 가 노드 용량을 실제보다 낙관해 **과배치**한다
- `memory = 900` 은 실측 838 대비 여유가 **62 MiB(7%)** 뿐이다. GC 스파이크 한 번에 OOMKill 이다

### ⚠️ 그런데 Phase 2 의 측정과도 어긋난다 — 착수 전 재측정이 필수다

[Phase 2](./phase-02-observability.md) 는 2026-08-20 에 **dev RSS p99 1,277 / max 1,287 MiB**
("prod 와 사실상 같다")로 기록했다. 11일 뒤 같은 지표가 **834** 다. 450 MiB 차이다.

**이 차이는 지금 규명할 수 없다.** Prometheus 보존이 **15일(또는 10 GiB)** 이라
Phase 2 가 본 창(2026-08-06~20)이 이미 보존 밖으로 나갔다. 재현이 불가능하다.

> 같은 조사를 반복하지 않도록: 두 값의 출처는 동일한 `container_memory_rss` 이고,
> 그 사이 dev 태스크 정의는 1182 → 1188 로 7회 재배포됐다. JVM 힙 옵션이 바뀌었을 가능성이
> 가장 크지만 **확인할 데이터가 남아 있지 않다.**

**따라서 이 Phase 착수 시점에 다시 14일치를 측정해서 값을 확정한다.** 다만 어느 쪽이 맞든
**`900` 은 부적절하다** — 834 면 여유가 7% 뿐이고, 1,277 이면 아예 초과한다.

```promql
# 착수 직전에 이 세 개를 다시 돌린다
max_over_time(container_memory_working_set_bytes{container_label_com_amazonaws_ecs_container_name="groble-dev-spring-api"}[14d])
quantile_over_time(0.99, container_memory_rss{container_label_com_amazonaws_ecs_container_name="groble-dev-spring-api"}[14d])
max(container_spec_memory_limit_bytes{container_label_com_amazonaws_ecs_container_name="groble-dev-spring-api"})
```

**함께 확인할 것**: 앱의 실제 `-Xmx`. Phase 2 는 "dev·prod 둘 다 `-Xmx900m` 이라 RSS 는
라이브 셋이 아니라 힙 상한이 결정한다"고 적어 뒀다. 힙 상한이 그대로라면 컨테이너 리밋은
**힙 + 메타스페이스 + 스레드 스택 + 네이티브** 를 덮어야 한다.
[Phase 7](./phase-07-prod-asg.md) 의 "JVM 힙 상한 수정" 과 같은 문제다.

---

## t3.small 예산이 성립하는지 — 8-a 가 선행 조건인 이유

dev 노드를 t3.medium(4 GiB) → **t3.small(2 GiB)** 로 낮추는 것이 이 Phase 의 전제다(계획서 §2.1).
2 GiB 에서 OS·ECS 에이전트 오버헤드(~400–500 MiB)를 빼면 태스크 예산이 **~1,000–1,300 MiB** 다.

| | 8-a 이전 | 8-a 이후 |
|---|---|---|
| dev-mysql | **256 MiB** | **0** (RDS) |
| dev-redis | 128 MiB | **0** (ElastiCache) |
| node-exporter | 48 MiB | 48 MiB |
| cAdvisor | 96 MiB | 96 MiB |
| dev API | **≥ 838** | ≥ 838 |
| **합계** | **1,366+** | **982+** |

**8-a·이 Phase 의 상태 외부화 없이는 t3.small 에 들어가지 않는다.**
그래도 여유가 크지 않으므로, 부족하면 **cAdvisor 를 256 → 160 MiB 로 조여 100 MiB 를 확보**한다
(계획서 §4 To-Do 4). 실측상 cAdvisor 사용량은 23.6 MiB 라 여유가 있다.

> `awsvpc` 모드 API 태스크는 노드당 **최대 2개**(ENI 제약)지만, t3.small 에서는
> **메모리가 먼저 1개로 묶는다.** 밀도의 상한이 여기서만 ENI 가 아니다.

---

## 절차

### A. Dev ElastiCache

1. **ElastiCache 생성** — `cache.t4g.micro`, **2c**, 단일 노드
   - 리소스는 **`aws_elasticache_replication_group`** (`num_cache_clusters = 1`,
     `automatic_failover_enabled = false`) — `aws_elasticache_cluster` 가 아니다.
     replica 추가를 온라인 변경으로 만들기 위함 (계획서 §2.3)
   - 앱은 `primary_endpoint_address` 를 본다
   - **Prod 노드와 공유하지 않는다**
   - 유지보수 창을 명시 지정한다. ⚠️ **기본값은 무작위이며 값은 UTC 다** —
     [8-a](./phase-08a-dev-rds.md) 의 RDS 창과 같은 함정이다. `sun:18:00-sun:19:00` UTC (KST 월 03~04시)
   - SG: API 태스크 SG 로부터 6379
2. `REDIS_HOST` 를 ElastiCache 엔드포인트로 → 재배포
   > **Prod 와 달리 stop-first 가 필요 없다.** [Phase 6](./phase-06-elasticache.md) 이 stop-first 를
   > 쓰는 이유는 결제 멱등성 키·재고 예약이 갈라지는 것을 막기 위함인데, dev 에는 지킬 결제 상태가 없다.
3. 구 dev Redis 컨테이너 서비스 제거

### B. Dev ASG 전환

4. [Phase 7](./phase-07-prod-asg.md) 과 동일한 절차 (Launch Template, ASG, capacity provider)

   Dev 는 t3.small 이라 **노드당 API 태스크가 1개**뿐이다. Prod 의 surge 방식을 쓸 수 없으므로
   축소 우선 방식으로 설정한다 (계획서 §2.1):

   ```hcl
   # 태스크 정의
   memoryReservation = <위 재측정으로 확정>   # 계획서의 800 은 실사용 834 보다 낮다
   memory            = <위 재측정으로 확정>   # 계획서의 900 은 여유가 7% 뿐이다

   # 서비스
   deployment_minimum_healthy_percent = 50    # desired 2 → 최소 1태스크
   deployment_maximum_percent         = 100   # 최대 2태스크 (노드당 1개)
   ```

   > **[Phase 5](./phase-05-deployment-controller.md) 의 임시값 `100/200` 을 여기서 To-Be 값으로 되돌린다.**
   > 임시값을 쓴 이유는 desired 1 에서 `50/100` 이 `min=ceil(0.5)=1` · `max=floor(1.0)=1` 로
   > 교착이기 때문이다. desired 2 가 되면서 그 제약이 사라진다.

   배포 시퀀스: `구2:신0 → 1:0 → 1:1 → 0:1 → 0:2`

   > ⚠️ `minimum_healthy_percent` 를 100 으로 두면 태스크를 먼저 내릴 수 없어 **배포가 교착 상태에 빠진다.**
   > 반드시 50 으로 낮춘다.

5. 구 Dev 노드 드레인 → 종료
   - `/opt/mysql-dev-data`(8-a 의 잔재)가 이 노드와 함께 사라진다

---

## 검증

- [ ] **착수 전** dev API 메모리 14일 재측정 완료 → `memoryReservation` / `memory` 확정
- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] Dev 에서 rolling 배포가 정상 수행되는지 — **promote 게이트의 전제**
- [ ] 배포 중 `1:1`(구/신 공존) 구간이 실제로 관측되는지 — 버전 공존 검증
- [ ] 신 노드에 `Cluster = groble-cluster` 태그가 붙어 Prometheus `ec2_sd` 에 잡히는지
      (⚠️ 누락되면 **경고 없이** 스크레이프 목록에서 빠진다)
- [ ] 신 노드에 SSM 접속이 되는지 — [Phase 9](./phase-09-access-path.md) 의 선행 조건
- [ ] t3.small 예산 실측 — 부족하면 cAdvisor 256 → 160 MiB
- [ ] ElastiCache 자동 스냅샷·유지보수 창이 **의도한 KST 시각**인지 (UTC 함정)

## 롤백

단계별로 이전 엔드포인트 복원. Dev 이므로 짧은 다운타임을 감수할 수 있다.

| 시점 | 되돌리기 |
|---|---|
| A (ElastiCache) | `REDIS_HOST` 를 노드 IP 로 되돌려 재배포. 컨테이너를 지우기 전까지 가능 |
| B (ASG) | 구 Dev 노드 재활성화 — [Phase 7](./phase-07-prod-asg.md) 과 동일 |

> 되돌릴 수 없게 되는 시점: **구 Dev 노드 종료.** 그 전에 신 노드에서 태스크 정상 기동 ·
> Prometheus 타깃 등록 · SSM 접속이 확인되어 있어야 한다.

---

[← Phase 8-a — Dev MySQL → RDS](./phase-08a-dev-rds.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 — 접근 경로 정리 →](./phase-09-access-path.md)
