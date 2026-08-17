# Phase 2 — 관측 선행 전환 (ASG보다 반드시 먼저)

> [← Phase 1](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 →](./phase-03-nat-gateway.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | ASG 도입 후 새 노드가 **관측 사각지대에 들어가는 것을 막는다.** 순서가 뒤바뀌면 노드가 조용히 사라지고, 하필 그 시점이 마이그레이션 중이라 가장 위험하다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 이전 이미지 태그로 롤백 |

---

## 2-0. API 태스크 워킹셋 측정 (선행 — Phase 1에서 이관) ⭐

**Phase 7·8의 용량 결정이 이 측정에 걸려 있다.** Prometheus를 손보는 이 Phase에서 함께 한다.

### 왜 필요한가

Phase 1의 기준선 수집에서 prod API 태스크 메모리가 **하드 리밋(1,500 MiB)의 91~100%**로 관측됐다.
그런데 14일간 `LiveTaskCount`가 1 미만으로 떨어진 적이 없다 — **OOM 킬 0회**.
리밋에 53%의 시간 동안 닿아 있으면서 죽지 않았다는 것은 대부분이 **회수 가능한 페이지 캐시**임을 시사한다.

문제는 `AWS/ECS` 지표(`MemoryUtilization`)가 **cgroup 사용량 = anonymous + 페이지 캐시**를 합쳐서 보여준다는 것이다.
배치(placement)에 쓸 `memoryReservation`은 **캐시를 제외한 실제 워킹셋**이어야 하는데, CloudWatch로는 이 둘을 분리할 수 없다.

### 측정 방법

cAdvisor가 이미 수집하고 있으므로 Prometheus 쿼리만 하면 된다.

```promql
# 워킹셋 (회수 불가에 가까운 실사용) — 이 값이 memoryReservation의 근거다
container_memory_working_set_bytes{name=~".*prod.*api.*"}

# RSS (anonymous만)
container_memory_rss{name=~".*prod.*api.*"}

# 캐시 (회수 가능)
container_memory_cache{name=~".*prod.*api.*"}
```

최소 며칠치의 **최대값**을 본다. 평균이 아니라 최대여야 한다 — 배치는 최악을 견뎌야 한다.

### 이 값으로 결정되는 것

| 대상 | 현재 계획 | 상태 |
|---|---|---|
| [Phase 7](./phase-07-prod-asg.md) 5번 `memory_reservation = 1000` | 계획서에 적힌 값 | ⚠️ **근거 없는 값이다.** 측정 결과로 대체할 것 |
| [Phase 8](./phase-08-dev-migration.md) 6번 dev `memory = 900` | t3.small 예산에 맞춘 값 | ⚠️ 같은 측정에 의존 |
| t3.medium 노드당 태스크 2개 수용 여부 | 여유 크지 않음(추정 ~3.3 GiB/4 GiB) | 워킹셋이 작으면 여유가 늘어난다 |

> ⚠️ **이 측정을 2-1보다 먼저 하는 이유**: `static_configs` → `ec2_sd_config`로 바꾸면 타깃 라벨
> 집합이 바뀌어 **기존 시계열이 종료되고 새 시계열이 시작된다.** 전환 후에 측정하려면 며칠을
> 다시 수집해야 한다. 지금 Prometheus에는 이미 15일치가 쌓여 있으므로 전환 전에 뽑는 것이 이득이다.

배경과 실측 근거는 [계획서 §2.1 "트래픽·자원 기준선"](../infra-ha-improvement-plan.md)과
[Phase 1](./phase-01-alarm-backstop.md)에 있다.

---

## 2-1. Prometheus `ec2_sd_config` 전환

1. ~~Prometheus Task Role에 `ec2:DescribeInstances` 인라인 정책 추가~~ — **불필요. 이미 있다.**
   `modules/services/monitoring/prometheus/main.tf`의 인라인 정책 `${environment}-prometheus-access`가 `ec2:DescribeInstances` /
   `DescribeAvailabilityZones` / `DescribeRegions`를 이미 부여한다 (AWS에서도 확인). 계획서 초안이 "현재 없음"으로 잘못 적고 있었다
2. **기존 3개 `aws_instance`에 `Cluster=groble-cluster`, `environment`, `Type` 태그가 붙어 있는지 확인**하고 없으면 추가 — `ec2_sd`는 인스턴스 태그를 본다. (Phase 7의 ASG는 태그 전파 설정으로 같은 키를 붙인다)
3. `groble-images` 저장소의 Prometheus config를 `static_configs` → `ec2_sd_config`로 변경
   - 태그 필터: `Cluster = groble-cluster`
   - relabel: EC2 태그 `environment`, `Type`을 라벨로 승격
   - 포트별 잡 분리: node-exporter(9100), cAdvisor(8081)
4. CI에서 `promtool check config` 게이트 추가
5. **"기대 타깃 수 미달" 알람의 기대값을 상수로 박지 않는다** — config baking 시 환경별 노드 수 변수에서 주입하거나, 최소한 "ASG desired 변경 시 함께 바꿀 것" 목록에 등재 (계획서 §2.4)
6. 새 이미지 태그로 Prometheus 서비스 배포

## 2-2. Grafana 프로비저닝 as-code

1. 현재 Grafana UI에서 **대시보드·데이터소스·알림 규칙을 JSON으로 export**
2. `groble-images`에 provisioning 구조로 정리 (`/etc/grafana/provisioning/{datasources,dashboards,alerting}`)
3. provisioned 대시보드는 **읽기 전용**으로 설정 (UI 편집분과 코드가 갈라지지 않게)
4. 새 이미지로 Grafana 서비스 배포

---

## 검증

- [ ] Prometheus `/targets`에서 **기존 노드 3대가 모두 UP**으로 잡히는지 (전환 전과 동일한 타깃 수)
- [ ] Grafana 대시보드가 프로비저닝으로 복원되었는지, 기존 패널이 정상 렌더되는지
- [ ] `up == 0` 알람과 **"기대 타깃 수 미달" 알람** 동작 확인
- [ ] **API 태스크 워킹셋 최대값을 기록**했는지 (2-0) — Phase 7·8의 `memoryReservation` 근거

## 롤백

이전 이미지 태그로 서비스 되돌리기. IAM 정책은 남겨둬도 무해하다.

> ⚠️ **이 Phase를 건너뛰고 Phase 7로 가지 않는다.** 새 ASG 노드가 스크레이프되지 않는 상태로 마이그레이션을 진행하면, 문제가 생겨도 지표가 없다.

---

[← Phase 1 — 알람 백스톱 확보](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 — NAT Gateway 전환 →](./phase-03-nat-gateway.md)
