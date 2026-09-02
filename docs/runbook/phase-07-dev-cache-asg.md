# Phase 7 — Dev ElastiCache + ASG 전환

> [← Phase 6](./phase-06-deployment-controller.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 8 →](./phase-08-prod-elasticache.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | ① Dev 를 Prod 와 같은 형태로 만들어 §3-5 의 promote 게이트가 실제로 의미를 갖게 한다 · ② **[8](./phase-08-prod-elasticache.md)·[9](./phase-09-prod-asg.md) 의 리허설** — 두 전환을 실트래픽 없는 곳에서 먼저 해본다 |
| **선행 조건** | **[5](./phase-05-dev-rds.md)**(노드 메모리 확보) · **[Phase 6](./phase-06-deployment-controller.md)**(rolling) |
| **사용자 영향** | Dev 만. 개발 작업이 없는 시간대 권장 |
| **되돌리기** | 단계별 |
| **비용** | **+$15/월** (ElastiCache `cache.t4g.micro`). 컴퓨트는 t3.medium → t3.small ×2 로 상쇄 |

## 🔁 이 문서가 ASG 절차의 원본이다

**같은 변경은 Dev 에서 먼저 하고 Prod 로 승격한다**(계획서 §3-5). 그래서 Phase 7~9 는 이렇게 배열된다.

| 변경 | Dev (먼저 — 이 문서) | Prod (나중) |
|---|---|---|
| Redis → ElastiCache | **A 단계** | [8](./phase-08-prod-elasticache.md) |
| 노드 → ASG / Launch Template | **B 단계** | [9](./phase-09-prod-asg.md) |

**아래 B 단계의 Launch Template·ASG·Capacity Provider 절차가 원본이고,
[9](./phase-09-prod-asg.md) 는 그것을 참조하며 Prod 고유의 차이만 적는다.**
여기서 실패하는 것은 Dev 에서 고치고 넘어간다 — Prod 에서 처음 만나지 않는 것이 이 배치의 목적이다.

> ⚠️ **이 리허설이 Prod 를 완전히 대변하지는 못한다.** Dev 는 t3.small 이라 노드당 API 태스크가 1개고,
> **Prod 의 surge 배치와 피크 시점 메모리·ENI 압력은 여기서 검증되지 않는다**(계획서 §2.1).
> 그 둘은 [9](./phase-09-prod-asg.md) 의 instance refresh 리허설에서 처음 실측한다.
> 여기서 덮이는 것은 **ElastiCache 엔드포인트 전환 · AL2023 AMI · Launch Template ·
> Capacity Provider managed draining · 태그 전파 · credential 프록시 · SSM 등록** 이다.

> **번호 이력.** 이 Phase 는 2026-08-31 이전에 "Phase 8"(Dev 전환)의 일부였고 RDS 이관 부분을
> **[5](./phase-05-dev-rds.md) 로 앞당겨 분리**했다. 2026-09-02 까지는 **Phase 9** 였으며 Prod 전환보다
> **뒤**에 있었다 — dev-first 규칙에 반해 앞으로 당겼다
> ([번호 이력](../infra-ha-migration-runbook.md#번호-이력--옛-문서pr-의-번호는-다를-수-있다) ①).

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
[Phase 9](./phase-09-prod-asg.md) 의 "JVM 힙 상한 수정" 과 같은 문제다.

---

## t3.small 예산이 성립하는지 — Phase 5 가 선행 조건인 이유

dev 노드를 t3.medium(4 GiB) → **t3.small(2 GiB)** 로 낮추는 것이 이 Phase 의 전제다(계획서 §2.1).
2 GiB 에서 OS·ECS 에이전트 오버헤드(~400–500 MiB)를 빼면 태스크 예산이 **~1,000–1,300 MiB** 다.

| | Phase 5 이전 | Phase 5 이후 |
|---|---|---|
| dev-mysql | **256 MiB** | **0** (RDS) |
| dev-redis | 128 MiB | **0** (ElastiCache) |
| node-exporter | 48 MiB | 48 MiB |
| cAdvisor | 96 MiB | 96 MiB |
| dev API | **≥ 838** | ≥ 838 |
| **합계** | **1,366+** | **982+** |

**Phase 5·이 Phase 의 상태 외부화 없이는 t3.small 에 들어가지 않는다.**
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
     [5](./phase-05-dev-rds.md) 의 RDS 창과 같은 함정이다. `sun:18:00-sun:19:00` UTC (KST 월 03~04시)
   - SG: API 태스크 SG 로부터 6379
2. `REDIS_HOST` 를 ElastiCache 엔드포인트로 → 재배포
   > **여기서는 stop-first 가 필요 없다 — Prod 에서는 필요하다.** [8](./phase-08-prod-elasticache.md) 이 stop-first 를
   > 쓰는 이유는 결제 멱등성 키·재고 예약이 두 저장소로 갈라지는 것을 막기 위함인데, dev 에는 지킬 결제 상태가 없다.
   > **따라서 이 단계는 stop-first 절차 자체를 리허설하지 못한다.** 여기서 검증되는 것은
   > 엔드포인트 전환·SG·앱의 ElastiCache 연결이고, stop-first 시퀀스는 [8](./phase-08-prod-elasticache.md) 에서 처음 수행한다.
3. 구 dev Redis 컨테이너 서비스 제거

### B. Dev ASG 전환 — **이 절차가 원본이다** ([9](./phase-09-prod-asg.md) 가 이것을 참조한다)

4. **Launch Template 작성**
   - AMI: SSM Parameter `/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id`
   - user_data: `/etc/ecs/ecs.config` 에 `ECS_CLUSTER`,
     `ECS_INSTANCE_ATTRIBUTES={"environment":"development"}`, `ECS_RESERVED_MEMORY=512`,
     `ECS_CONTAINER_STOP_TIMEOUT`([Phase 6](./phase-06-deployment-controller.md) §3-3 에서 확정한 값)
   - 인스턴스 프로파일: 기존 ECS 인스턴스 롤 + `AmazonSSMManagedInstanceCore`
   - **키페어 지정하지 않음**
   - 루트 볼륨 30GB gp3, 암호화
   - ⚠️ **구 노드의 `user_data` 가 만들던 1 GiB 스왑파일이 사라진다.** dev 에서도 JVM 힙 상한이
     컨테이너 하드리밋을 넘지 않는지 확인할 것 — [9](./phase-09-prod-asg.md) 의 차단 조건 1과 같은 문제다

5. **ASG 생성** — `desired = 2`, **2c 서브넷 고정**, 인스턴스 타입 **`t3.small` 단일**
   - ⚠️ **`t3a.small` 을 mixed instances 로 섞지 않는다.** 2026-08-30 실측상 `t3a.small` 만
     **ENI 가 2개**(secondary 1)라 awsvpc 태스크가 노드당 1개로 묶인다 — t3a 가 t3 와 같다는 것은
     medium 이상에서만 참이다 (계획서 §2.1). Prod([9](./phase-09-prod-asg.md))는
     `t3a.medium` 이 안전하므로 mixed 를 쓴다 — **이 한 줄이 Dev·Prod 의 차이다**
   - instance refresh preferences: `min_healthy_percentage = 100`,
     `max_healthy_percentage = 200` (launch-before-terminate)
   - **태그 전파** — `ec2_sd` 가 새 노드를 보려면 인스턴스에 태그가 붙어야 한다 (계획서 §2.4).
     현재 dev 노드(`aws_instance.dev_instance`)가 달고 있는 값과 **일치시킨다**:
     ```hcl
     tag { key = "Name"        value = "groble-develop-instance" propagate_at_launch = true }
     tag { key = "Cluster"     value = "groble-cluster"          propagate_at_launch = true }
     tag { key = "environment" value = "development"             propagate_at_launch = true }
     tag { key = "Type"        value = "Development"             propagate_at_launch = true }
     ```
     Launch Template `tag_specifications` 와 **중복 정의하지 않는다** — 한 곳으로 통일

     ⚠️ **`Name` 을 빠뜨리지 말 것.** Prometheus 가 `Name` → `instance_name` 라벨로 승격하므로,
     빠지면 **신 노드의 `instance_name` 라벨이 비어** 대시보드에서 노드를 구분할 수 없게 된다.
     ASG 는 `Name` 을 자동으로 붙이지 않는다.
     ⚠️ `Type` 도 **기존 값(`Development`)을 그대로 쓴다.** 값을 바꾸면 `node_type` 라벨이
     신·구 노드 간에 갈린다. 바꾸려면 의도한 차이임을 문서화할 것

6. **Capacity Provider 생성 및 클러스터 연결**
   ```hcl
   managed_draining = "ENABLED"
   managed_scaling { status = "DISABLED" }   # 고정 크기 ASG
   ```
   - ⚠️ [Phase 6](./phase-06-deployment-controller.md) 에서 만든 신 서비스에 `capacity_provider_strategy` 를
     붙이는 변경은 **provider 버전에 따라 서비스 재생성을 강제할 수 있다** (계획서 §2.1).
     **plan 에서 `aws_ecs_service` 가 replace 로 잡히면 apply 하지 않는다.**
     launch type 서비스도 컨테이너 인스턴스 DRAINING 으로 정상 드레인되므로, 이 경우 CP 전략 부착은
     미루고 managed draining 만으로 진행한다 (10번 리허설에서 실제 드레인 동작으로 확인)
   - **여기서 replace 가 잡히는지 여부가 [9](./phase-09-prod-asg.md) 에 그대로 인계된다** — 결과를 기록할 것

7. **신 노드 검증** (구 노드와 병존 상태)
   - [ ] ECS 클러스터에 컨테이너 인스턴스로 등록되었는지
   - [ ] `environment=development` 속성이 붙었는지
   - [ ] EC2 에서 인스턴스에 `Name`·`Cluster`·`environment`·`Type` 태그가 붙었는지
         (`aws ec2 describe-instances --filters Name=tag:Cluster,Values=groble-cluster`)
   - [ ] Prometheus `/targets` 에 **자동으로 나타나는지** (Phase 2 의 `ec2_sd` 검증) —
         위 태그가 없으면 여기서 조용히 빠진다
   - [ ] `aws ssm start-session` 으로 접속되는지
   - [ ] credential 프록시 정상 — 태스크에서 AWS API 호출 성공 확인

8. **태스크 정의·서비스 설정 변경**

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

   > **[Phase 6](./phase-06-deployment-controller.md) 의 임시값 `100/200` 을 여기서 To-Be 값으로 되돌린다.**
   > 임시값을 쓴 이유는 desired 1 에서 `50/100` 이 `min=ceil(0.5)=1` · `max=floor(1.0)=1` 로
   > 교착이기 때문이다. desired 2 가 되면서 그 제약이 사라진다.

   배포 시퀀스: `구2:신0 → 1:0 → 1:1 → 0:1 → 0:2`

   > ⚠️ `minimum_healthy_percent` 를 100 으로 두면 태스크를 먼저 내릴 수 없어 **배포가 교착 상태에 빠진다.**
   > 반드시 50 으로 낮춘다.

9. **구 Dev 노드를 DRAINING 으로 전환 → 태스크 이동 확인 → 종료**
   ```bash
   aws ecs update-container-instances-state --cluster groble-cluster \
     --container-instances <old-instance-arn> --status DRAINING
   ```
   - `/opt/mysql-dev-data`([5](./phase-05-dev-rds.md) 의 잔재)가 이 노드와 함께 사라진다

10. **instance refresh 리허설** — 실제로 1회 수행해 무중단 교체가 동작하는지 확인 ⭐
    - 여기서 확인하는 것은 **managed draining 이 태스크를 실제로 옮기는가**이다.
      실트래픽 하의 5xx 는 [9](./phase-09-prod-asg.md) 에서 측정한다

---

## 검증

- [ ] **착수 전** dev API 메모리 14일 재측정 완료 → `memoryReservation` / `memory` 확정
- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] Dev 에서 rolling 배포가 정상 수행되는지 — **promote 게이트의 전제**
- [ ] 배포 중 `1:1`(구/신 공존) 구간이 실제로 관측되는지 — 버전 공존 검증
- [ ] 신 노드에 `Cluster = groble-cluster` 태그가 붙어 Prometheus `ec2_sd` 에 잡히는지
      (⚠️ 누락되면 **경고 없이** 스크레이프 목록에서 빠진다)
- [ ] 신 노드에 SSM 접속이 되는지 — [Phase 10](./phase-10-access-path.md) 의 선행 조건
- [ ] t3.small 예산 실측 — 부족하면 cAdvisor 256 → 160 MiB
- [ ] ElastiCache 자동 스냅샷·유지보수 창이 **의도한 KST 시각**인지 (UTC 함정)
- [ ] **instance refresh 1회 성공** — 교체 중 dev 태스크가 재배치되는지

### [8](./phase-08-prod-elasticache.md)·[9](./phase-09-prod-asg.md) 로 인계할 것 — 리허설의 산출물

여기서 나온 값·오류는 Prod 문서에 반영한 뒤 진입한다.

- [ ] Capacity Provider 부착 시 `aws_ecs_service` replace 가 잡혔는지 (6번) — Prod plan 판단의 근거
- [ ] AL2023 노드에서 credential 프록시가 재부팅 후에도 유지되는지
- [ ] `ec2_sd` 태그 전파에서 빠뜨린 태그가 있었는지
- [ ] ElastiCache 전환 시 앱이 재연결에 실패한 지점이 있었는지
- [ ] 노드 복구 소요 시간 (강제 종료 → 태스크 RUNNING) 개략치

## 롤백

단계별로 이전 엔드포인트 복원. Dev 이므로 짧은 다운타임을 감수할 수 있다.

| 시점 | 되돌리기 |
|---|---|
| A (ElastiCache) | `REDIS_HOST` 를 노드 IP 로 되돌려 재배포. 컨테이너를 지우기 전까지 가능 |
| B (ASG) | 구 Dev 노드를 `ACTIVE` 로 되돌리고 ASG `desired = 0`. **9번(구 노드 종료) 전까지 완전히 되돌릴 수 있다** |

> 되돌릴 수 없게 되는 시점: **구 Dev 노드 종료.** 그 전에 신 노드에서 태스크 정상 기동 ·
> Prometheus 타깃 등록 · SSM 접속이 확인되어 있어야 한다.

---

[← Phase 6 — 배포 컨트롤러 전환](./phase-06-deployment-controller.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 8 — Prod Redis → ElastiCache →](./phase-08-prod-elasticache.md)
