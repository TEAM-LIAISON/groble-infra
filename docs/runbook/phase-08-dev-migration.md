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

## 검증

- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] Dev에서 rolling 배포가 정상 수행되는지 — **promote 게이트의 전제**
- [ ] 배포 중 `1:1`(구/신 공존) 구간이 실제로 관측되는지 — 버전 공존 검증
- [ ] **Dev API 실사용 메모리 실측** → 900이 적정한지 확인, 부족하면 cAdvisor task memory를 256 → 160으로 조여 100MiB 확보 (계획서 §4 To-Do 4)
- [ ] Dev RDS 자동 백업이 설정되었는지

## 롤백

단계별로 이전 엔드포인트 복원. Dev이므로 짧은 다운타임을 감수할 수 있다.

> 되돌릴 수 없게 되는 시점: **구 Dev MySQL 컨테이너 제거.** 그 전에 RDS로 데이터 복원이 완료·검증되었는지 확인한다.

---

[← Phase 7 — Prod ASG 전환](./phase-07-prod-asg.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 — 접근 경로 정리 →](./phase-09-access-path.md)
