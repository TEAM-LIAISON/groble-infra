# Phase 8 — Dev 전환

> [← Phase 7](./phase-07-prod-asg.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 →](./phase-09-access-path.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | Dev를 Prod와 같은 형태로 만들어 §3-5의 promote 게이트가 실제로 의미를 갖게 한다 |
| **사용자 영향** | Dev만. 개발 작업이 없는 시간대 권장 |
| **되돌리기** | 단계별 |

---

## 절차

1. **Dev RDS 생성** (`db.t4g.micro`, 2c, 단일 AZ, 자동 백업)
2. 현재 Dev MySQL 컨테이너에서 **데이터 덤프 → RDS 복원**
   ```bash
   mysqldump ... > dev.sql && mysql -h <rds-endpoint> < dev.sql
   ```
3. **Dev ElastiCache 생성** (`cache.t4g.micro`, 2c) — Prod와 동일하게 `aws_elasticache_replication_group` 리소스로 (모듈을 공유하면 자연히 그렇게 된다)
4. Dev 앱의 `DB_HOST` / `REDIS_HOST` 변경 → 재배포
5. 구 Dev MySQL·Redis 컨테이너 서비스 제거
6. **Dev ASG 전환** — [Phase 7](./phase-07-prod-asg.md)과 동일한 절차 (Launch Template, ASG, capacity provider)

   Dev는 t3.small(2GiB)이라 **노드당 API 태스크가 1개**뿐이다. Prod의 surge 방식을 쓸 수 없으므로 축소 우선 방식으로 설정한다 (계획서 §2.1):

   ```hcl
   # 태스크 정의
   memoryReservation = 800
   memory            = 900     # 현재 1500 — t3.small 예산(~1000MiB)에 맞춰 하향

   # 서비스
   deployment_minimum_healthy_percent = 50    # desired 2 → 최소 1태스크
   deployment_maximum_percent         = 100   # 최대 2태스크 (노드당 1개)
   ```

   배포 시퀀스: `구2:신0 → 1:0 → 1:1 → 0:1 → 0:2`

   > ⚠️ `minimum_healthy_percent`를 100으로 두면 태스크를 먼저 내릴 수 없어 **배포가 교착 상태에 빠진다.** 반드시 50으로 낮춘다.

7. 구 Dev 노드 드레인 → 종료

---

## 이관 전까지의 상태 — Dev MySQL 컨테이너는 이미 리밋에 붙어 있다

> Phase 2 에서 `컨테이너 메모리 하드리밋 근접` 알람이 dev-mysql 로 계속 발화해 조사했다.
> **리밋 상향(256 → 384 MiB)을 검토했으나, 어차피 이 Phase 에서 컨테이너 자체가 사라지므로
> 상향하지 않기로 했다.** 여기까지는 알람 발화를 감수한다.

**측정 (2026-08-20, 운영 Prometheus, 직전 14일)**

| 항목 | 값 |
|---|---|
| 컨테이너 하드리밋 | 256 MiB |
| RSS / page cache | **221.8** / 22.7 MiB → 회수 가능한 여유가 **34 MiB 뿐** |
| working set 비율 | **99.1%** (알람 임계 90%) |
| **컨테이너 인스턴스 수 (14일)** | **5개** — 즉 5번 재시작했다 |
| 같은 기간 dev-redis | **1개** (2025-11-11 시작 이후 그대로) |
| dev 노드 부팅 후 경과 | 281일 (노드 사건 아님) |
| 태스크 정의 | 14일 내내 **rev 40 고정** (재배포 아님) |
| 종료된 컨테이너들의 **마지막 usage** | 253.1 · 255.4 · 255.8 · 255.8 · **256.0** MiB |

재시작은 dev-mysql 고유이고, 종료 직전 전부 하드리밋에 붙어 있었다.
**다만 사인은 특정하지 못했다** — OOM kill 인지, 메모리 압박으로 `mysqladmin ping`(timeout 10s × retries 3)
헬스체크가 연속 실패해 ECS 가 교체한 것인지 구분할 수 없다.

> 판별이 막힌 이유 세 가지. 같은 조사를 반복하지 않도록 적어 둔다.
> - `container_memory_failcnt` 는 **cgroup v1 지표**라 v2 노드에서 전부 0 으로 나온다
> - ECS 는 중지된 태스크의 `stoppedReason` 을 **1시간만 보관**한다
> - **MySQL 컨테이너 로그는 Loki 로 가지 않는다** (Loki 에는 Spring 앱만 있다)
>
> 다음 재시작을 잡으려면 발생 직후 1시간 안에 `aws ecs describe-tasks --desired-status STOPPED` 를 봐야 한다.

**RDS 사이징 참고**: 현재 실사용 RSS 가 222 MiB 이고 버퍼풀은 128 MiB 다.
`db.t4g.micro`(1 GiB)면 충분하되, 이 값이 "리밋에 눌린 상태의 사용량"임을 감안할 것.

### ⚠️ 이관 중 걸리는 함정 2가지

**① `MYSQL_INNODB_BUFFER_POOL_SIZE` 는 무효다**

`modules/services/development/mysql-service/main.tf` 의 태스크 정의에
`MYSQL_INNODB_BUFFER_POOL_SIZE = "128M"` 이 환경변수로 들어 있는데,
**공식 `mysql:8.0` 이미지는 이 변수를 읽지 않는다.** 버퍼풀은 MySQL 8 기본값 128 MiB 이고,
우연히 값이 같아 지금까지 문제가 드러나지 않았다.
→ **이 변수를 고쳐서 메모리를 조절하려는 시도는 아무 효과가 없다.** 실제로 바꾸려면
`--innodb-buffer-pool-size` 를 `command` 로 넘기거나 my.cnf 를 마운트해야 한다.

**② `ignore_changes = [task_definition]` 때문에 태스크 정의 변경이 조용히 배포되지 않는다**

`aws_ecs_service.mysql_service` 에 `lifecycle { ignore_changes = [task_definition, desired_count] }`
가 걸려 있다. **태스크 정의를 고치면 새 리비전만 만들어지고 서비스는 옛 리비전을 계속 돌린다.**
`terraform plan` 은 성공하는데 실물은 안 바뀌므로 조용히 어긋난다 —
rev 40 이 14일간 고정돼 있던 것도 이 때문이다.

API 서비스가 `task_definition` 을 무시하는 것은 **CodeDeploy 가 그것을 소유**하기 때문인데,
MySQL 에는 CodeDeploy 가 없다. 같은 종류인 **dev-redis 에는 lifecycle 이 아예 없어** 서로 어긋나 있다.

| 서비스 | `ignore_changes` | 정당한가 |
|---|---|---|
| dev-api · prod-api | `[task_definition, load_balancer]` | ✅ CodeDeploy 소유 |
| **dev-mysql** | `[task_definition, desired_count]` | ❌ 이 Phase 에서 서비스째 제거되므로 자연 해소 |
| **prod-redis** | `[task_definition, desired_count]` | ❌ **남는다 — 아래 참조** |
| dev-redis | 없음 | — |

> 🔴 **prod-redis 에도 같은 함정이 있다.** [Phase 6](./phase-06-elasticache.md) 에서 ElastiCache 로
> 이관하며 서비스가 제거될 때까지, **prod Redis 태스크 정의를 고쳐도 배포되지 않는다.**
> 급히 고쳐야 할 일이 생기면 `aws ecs update-service --force-new-deployment --task-definition <family>:<rev>`
> 로 강제 배포해야 한다. Redis 컨테이너 재시작은 결제 멱등성 키·재고 예약 유실로 직결되므로
> (CLAUDE.md 의 Redis 표 참조) 이 사실을 모르고 "고쳤는데 왜 그대로지"를 반복하는 상황이 가장 위험하다.

---

## 검증

- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] Dev에서 rolling 배포가 정상 수행되는지 — **promote 게이트의 전제**
- [ ] 배포 중 `1:1`(구/신 공존) 구간이 실제로 관측되는지 — 버전 공존 검증
- [ ] **Dev API 실사용 메모리 실측** → 900이 적정한지 확인, 부족하면 cAdvisor task memory를 256 → 160으로 조여 100MiB 확보 (계획서 §4 To-Do 4)
- [ ] Dev RDS 자동 백업이 설정되었는지
- [ ] 구 Dev MySQL 컨테이너 제거 후 **`컨테이너 메모리 하드리밋 근접` 알람이 멎는지** (Phase 2 부터 계속 발화 중이었다)

## 롤백

단계별로 이전 엔드포인트 복원. Dev이므로 짧은 다운타임을 감수할 수 있다.

> 되돌릴 수 없게 되는 시점: **구 Dev MySQL 컨테이너 제거.** 그 전에 RDS로 데이터 복원이 완료·검증되었는지 확인한다.

---

[← Phase 7 — Prod ASG 전환](./phase-07-prod-asg.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 — 접근 경로 정리 →](./phase-09-access-path.md)
