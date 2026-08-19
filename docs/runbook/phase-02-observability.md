# Phase 2 — 관측 선행 전환 (ASG보다 반드시 먼저)

> [← Phase 1](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 →](./phase-03-nat-gateway.md)

| | |
|---|---|
| **상태** | **진행 중** — 2-0 완료 · 2-1 config 전환 PR 대기 · 2-2 미착수 |
| **목적** | ASG 도입 후 새 노드가 **관측 사각지대에 들어가는 것을 막는다.** 순서가 뒤바뀌면 노드가 조용히 사라지고, 하필 그 시점이 마이그레이션 중이라 가장 위험하다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 이전 이미지 태그로 롤백 |

---

## 2-0. API 태스크 워킹셋 측정 (선행 — Phase 1에서 이관) ✅ **완료**

**측정 조건**: 운영 Prometheus(`10.0.1.193:9090`), 2026-08-18 기준 직전 15일, 1분 해상도.
배포마다 태스크 정의 리비전이 컨테이너 이름에 박혀 시계열이 갈리므로(prod 17개·dev 50개),
집계식 위에 서브쿼리를 걸어 **단일 타임라인**으로 산출했다.

### 결과 요약 — 당초 가설은 반증되었다

Phase 1은 "리밋에 닿아 있으면서 OOM이 없으니 대부분 회수 가능한 페이지 캐시일 것"으로 추정했다.
**틀렸다.**

| prod API (15일) | 값 |
|---|---|
| 컨테이너 RSS p50 / p90 / max | 1,274 / 1,484 / **1,493 MiB** |
| 컨테이너 page cache p99 | **108 MiB** |
| RSS > 1,400 MiB 인 시간 비율 | **47.6%** |
| 컨테이너 하드리밋 | 1,500 MiB (15일간 변동 없음) |
| OOM kill | 0회 |

리밋을 채우고 있는 것은 캐시가 아니라 **거의 전부 anonymous 메모리**다.

### 진짜 원인 — JVM이 호스트 RAM 기준으로 힙 상한을 잡고 있다

`groble-backend/Dockerfile`의 `-XX:MaxRAMPercentage=75.0`이 컨테이너 리밋이 아니라 **노드 전체 RAM**에 적용된다.

| 항목 | 값 |
|---|---|
| JVM 힙 상한 (`jvm_memory_max_bytes{id="G1 Old Gen"}`) | **2,878 MiB** |
| EC2 노드 전체 RAM (t3.medium) | 3,837 MiB |
| 컨테이너 하드리밋 | 1,500 MiB |

`3,837 × 0.75 = 2,877.75` — 관측값과 정확히 일치한다. 컨테이너 기준이었다면 `1,500 × 0.75 = 1,125 MiB`여야 한다.
**JVM은 cgroup이 죽이는 지점의 약 2배를 자기 예산으로 알고 동작하고 있다.**

그 결과 G1이 메모리 압박을 느끼지 못해 회수를 미루고 힙만 계속 커밋한다.

| prod API (15일) | 값 |
|---|---|
| heap **used** 중앙값 / p99 / max | 522 / 1,362 / **1,602 MiB** ← 리밋 초과 |
| heap **committed** max | **1,766 MiB** ← 리밋 초과 |

### 안 죽는 이유 — 노드 스왑이 받아내고 있다

`prod_user_data.sh`가 만드는 **1 GiB 스왑파일**이 초과분을 흡수한다.

| prod 노드 (15일) | 값 |
|---|---|
| 스왑 총량 / **최대 사용** | 1,024 MiB / **947 MiB** |
| 컨테이너 스왑 사용 max | 915 MiB |
| 스왑 I/O max | **pswpin 1,211 · pswpout 1,380 pages/s** (≈5 MiB/s) |
| `MemAvailable` 최소 | **365 MiB** (3,837 MiB 노드에서) |
| **GC pause (`jvm_gc_pause_seconds_max`)** | p50 **8 ms** · p99 **145 ms** · **최대 2,584 ms** |
| GC 오버헤드 최대 (`jvm_gc_overhead`) | 1.52% |

**GC는 평소엔 건강하다(p50 8 ms, 오버헤드 1.5%). 문제는 드물게 발생하는 초 단위 정지다** — 최대 2.6초.
이 정지는 스왑 때문이라고 볼 근거가 있다. GC pause 상위 10개 시점을 같은 시각의 스왑인 속도와 대조하면
상위 구간은 `pswpin` 22~211 pages/s 를 동반하는 반면, **pause 하위 200개 구간의 스왑인 중앙값은 0**이다.
큰 수집이 스왑아웃된 힙 페이지를 밟을 때만 초 단위로 멈추는 것으로, 기전이 일관된다.

2.6초 정지는 사용자에게 그대로 노출되고, ALB 헬스체크·타임아웃을 건드릴 수 있는 크기다.

**JVM 힙 일부가 디스크에 올라간 채로 서비스 중이다.**

> 📌 **정정.** 이 문서의 초판은 이 자리에 "GC 평균 pause 최대 463 ms — G1 정상치의 10배"라고 적었다.
> 그 값은 `rate(pause_sum)/rate(pause_count)`(5분 창 평균)에서 나온 것으로, 수집이 없는 구간에서
> `inf`/`NaN`이 되는 취약한 식이었고 **상시 성능 저하인 것처럼 과장**돼 있었다.
> Micrometer가 직접 재는 `jvm_gc_pause_seconds_max` 로 다시 측정한 결과가 위 표다.
> **판단(=JVM 힙 상한 수정)은 달라지지 않는다** — 오히려 최대 정지는 463 ms 가 아니라 2,584 ms 로 더 나쁘다.

### 진짜 워킹셋 — GC 후 라이브 데이터

`jvm_memory_used_bytes`에는 라이브 객체와 미회수 쓰레기가 섞여 있어 사이징 근거가 될 수 없다.
쓰레기가 걷힌 뒤의 값(`jvm_gc_live_data_size_bytes`, major GC 직후 old gen)이 실제 필요량이다.

| | prod | dev |
|---|---|---|
| p50 | 258 MiB | 169 MiB |
| p99 | 443 MiB | 304 MiB |
| **최대** | **510.5 MiB** | 304.6 MiB |

**heap used p99(1,362 MiB)는 실제 필요량의 약 2.7배가 부풀려진 값이었다.**

### 이 측정으로 결정된 것

| 대상 | 결론 |
|---|---|
| JVM 힙 상한 | **`-Xms512m -Xmx900m`** (피크 라이브 셋 510 MiB의 1.76배). `-Xms`를 `-Xmx`와 같게 두지 않는다 — 컨테이너 예산 여유가 200 MiB뿐이라 상시 커밋하면 여유가 사라진다 |
| 컨테이너 하드리밋 1,500 MiB | **유지.** 상향 불필요 → 노드 사이징 재검토로 번지지 않는다 |
| [Phase 7](./phase-07-prod-asg.md) `memory_reservation` | ⚠️ **아직 확정 못 한다.** 현재 관측되는 1.5 GiB는 오설정이 만든 값이라 그대로 쓰면 오설정을 인프라에 고착시킨다. **JVM 수정 배포 후 2~3일 재측정하여 확정.** 잠정 예상 1,100~1,300 MiB |
| [Phase 8](./phase-08-dev-migration.md) dev `memory` | 같은 재측정에 의존. dev 라이브 셋은 305 MiB로 prod보다 작다 |
| t3.medium 노드당 태스크 2개 수용 | 수용 가능할 전망 (2 × ~1,300 MiB + 노드 오버헤드 < 3,837 MiB). 어차피 **ENI 3개 제약으로 노드당 awsvpc 태스크는 최대 2개**가 상한이다 |

### ⚠️ Phase 7 차단 조건

**지금 OOM을 막고 있는 스왑파일은 AMI 기능이 아니라 현재 노드의 `user_data`가 만드는 것이다.**
[Phase 7](./phase-07-prod-asg.md)에서 노드가 ECS-optimized AL2023 AMI + Launch Template으로 교체되면 이 스왑은 사라진다.

> **JVM 설정을 그대로 둔 채 노드를 교체하면 새 ASG 노드에서 prod API가 OOM kill로 종료된다.**
> 하필 마이그레이션 도중이라 원인 판별이 가장 어려운 시점이다.

### 후속 조치

`groble-backend`는 별도 레포이므로 **작업 요청서**를 작성해 전달했다 —
[`docs/handoff/backend-jvm-heap-limit.md`](../handoff/backend-jvm-heap-limit.md)

- [x] 백엔드 Dockerfile 수정 — [groble-backend#826](https://github.com/TEAM-LIAISON/groble-backend/pull/826) 머지 (2026-08-19, `2f7ab40`).
      요청서의 **방식 A**(Dockerfile 직접 고정) 채택: `-Xms512m -Xmx900m -XX:+ExitOnOutOfMemoryError`
- [x] **dev 배포 완료** — 아래 검증 결과 참조
- [ ] **prod 배포** — 미완료. 현재 prod 태스크는 여전히 리비전 511, 힙 상한 2,878 MiB
- [ ] prod 배포 후 2~3일 재측정 → Phase 7·8의 `memoryReservation` 확정

### dev 배포 후 검증 (가동 10.4시간 시점)

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| JVM 힙 상한 | 2,878 MiB | **900 MiB** |
| 컨테이너 RSS | p50 1,084 / max 1,493 MiB | **1,032 MiB (평탄)** |
| heap committed | max 1,766 MiB(prod 기준) | **590 MiB** — 상한 900 을 다 쓰지도 않는다 |
| 노드 스왑 사용 | max 748 MiB | **273 MiB** |
| GC 최대 pause | 107 ms | **61 ms** |
| GC 오버헤드 | 0.130% | **0.044%** |

⚠️ **dev 결과를 prod에 그대로 대입하면 안 된다.** dev 라이브 셋은 181 MiB 로 prod(510 MiB)의 1/3 수준이라
애초에 압박이 없던 환경이다. dev 검증이 말해주는 것은 "**수정이 무언가를 망가뜨리지 않는다**"까지다.

**prod 예상치** — dev 실측에서 비힙+오버헤드는 RSS 1,032 − heap committed 590 = **약 442 MiB**.
prod 는 라이브 셋이 커서 힙이 상한 900 MiB 근처에 머물 것이므로 RSS ≈ 900 + 450~480 = **약 1,350~1,380 MiB**.
하드리밋 1,500 MiB 대비 **여유가 120~150 MiB 로 얇다.** 배포 후 RSS 가 1,400 MiB 를 넘어 머물면
요청서 6절의 폴백대로 `-Xmx800m` 으로 낮춘다.
- [ ] (미규명) JDK 17이 왜 컨테이너 리밋을 인식하지 못하는지. `-Xmx` 명시로 우회하므로 수정에는 영향 없으나 근본 원인은 아니다. 진단하려면 컨테이너 내부에서 `java -XshowSettings:system` / cgroup 파일 확인이 필요한데, **prod 컨테이너에 프로세스를 띄우는 일이라 dev 노드나 로컬 재현으로 할 것**

---

## 2-1. Prometheus `ec2_sd_config` 전환

**PR**: [TEAM-LIAISON/groble-images#3](https://github.com/TEAM-LIAISON/groble-images/pull/3) (CI 통과, 머지 대기)

1. ~~Prometheus Task Role에 `ec2:DescribeInstances` 인라인 정책 추가~~ — ✅ **불필요. 이미 있다.**
   `modules/services/monitoring/prometheus/main.tf`의 인라인 정책 `${environment}-prometheus-access`가 `ec2:DescribeInstances` /
   `DescribeAvailabilityZones` / `DescribeRegions`를 이미 부여한다 (AWS에서도 확인)
2. ✅ **기존 3개 `aws_instance`의 태그 확인 완료** — 코드([`ecs-cluster/main.tf`](../../modules/platform/ecs-cluster/main.tf))와 AWS 실물 양쪽에서 확인했고, 추가 작업은 없었다

   | 인스턴스 | Name | environment | Type | Cluster | 사설 IP |
   |---|---|---|---|---|---|
   | 모니터링 | `groble-monitoring-instance` | `monitoring` | `Monitoring` | `groble-cluster` | 10.0.1.193 |
   | 운영 | `groble-prod-instance-1` | `production` | `Production` | `groble-cluster` | 10.0.11.62 |
   | 개발 | `groble-develop-instance` | `development` | `Development` | `groble-cluster` | 10.0.12.215 |

3. ✅ `groble-images`의 Prometheus config를 `static_configs` → `ec2_sd_config`로 변경
   - 태그 필터: `tag:Cluster = groble-cluster` **AND** `instance-state-name = running`
   - relabel: `environment` / `Name`→`instance_name` / `Type`→`node_type` / `instance_id` / `availability_zone`
   - 포트별 잡 분리: node-exporter(9100), cAdvisor(8081)
   - **라벨 호환성**: `environment` / `instance_name` 은 전환 전과 같은 값을 산출한다.
     `port` 지정으로 `__address__`가 `<사설IP>:<port>`가 되어 `instance` 라벨도 동일하다.
   - ⚠️ 단 `node_type` / `instance_id` / `availability_zone` 3개가 **추가되므로 라벨 집합이 바뀌어 전환 시점에 시계열이 한 번 갈라진다.**
     라벨 매처는 부분 일치라 기존 쿼리·대시보드는 그대로 동작한다. Phase 7에서 필요한 라벨이므로 **사용자 영향이 없는 지금** 끊는 편이 낫다고 판단했다
4. ~~CI에서 `promtool check config` 게이트 추가~~ — ✅ **이미 있었다.** `.github/workflows/build.yml`의 Validate config 스텝
5. ⏭ **"기대 타깃 수 미달" 알람** → **Grafana 알림으로 결정. [2-2](#2-2-grafana-프로비저닝-as-code)에서 프로비저닝한다**
   (Alertmanager가 배포돼 있지 않고, 2-2가 어차피 Grafana `alerting` 프로비저닝 작업이라 새 운영 구성요소 없이 붙는다)
6. ⏳ 새 이미지 태그로 Prometheus 서비스 배포 — `v2.45.0-3c2a266` (현재 `v2.45.0-5acea36`)

### ⚠️ 이 전환이 만드는 새 실패 모드

`ec2_sd`는 AWS API 호출에 의존한다. 노드 재부팅으로 credential 프록시 iptables(`169.254.170.2` DNAT)가 사라지면
디스커버리가 통째로 실패하는데, 이때 타깃은 `down`이 아니라 **목록에서 사라져 `up == 0` 알람이 뜨지 않는다.**
→ **"기대 타깃 수 미달" 알람이 없으면 이 고장을 못 잡는다.** 5번이 선택 사항이 아닌 이유다.

**성립 조건 — 태그 전파.** Phase 7의 ASG/Launch Template에서 `Cluster`·`environment`·`Name`·`Type` 태그가
인스턴스로 전파되지 않으면 새 노드는 경고 없이 스크레이프 목록에서 누락된다.

### 범위 조정 — `spring-apps` 잡은 이 전환으로 해결되지 않는다

당초 이 Phase에서 함께 처리하려 했으나, 확인 결과 **`ec2_sd`로는 불가능하다.**
API 태스크는 `awsvpc` 모드라 태스크마다 별도 ENI(고유 사설 IP)를 갖는데, `ec2_sd`가 발견하는 것은
**EC2 *인스턴스*이지 태스크 ENI가 아니다.**

현재 이 잡은 공개 ALB(`api.groble.im:443`)를 경유하며 한계가 두 가지다.

1. `/actuator/prometheus`가 인터넷에 노출된 상태에 의존한다
2. **`desired_count`를 2 이상으로 올리면** ALB 라운드로빈 때문에 서로 다른 태스크의 카운터가 한 시계열에 섞여
   `rate()`/`increase()`가 **에러 없이 틀린 값**을 낸다

태스크 단위 스크레이프에는 **ECS Service Discovery(Cloud Map) 등록 + `dns_sd_configs`(type A)** 가 필요하며,
Terraform 변경을 수반한다. **`desired_count`를 올리기 전에 반드시 선행되어야 한다** →
[Phase 7](./phase-07-prod-asg.md)의 선행 항목으로 이관.

## 2-2. Grafana 프로비저닝 as-code

> 현재 대시보드·데이터소스가 노드 로컬 SQLite(`/opt/grafana/data`)에만 있어 **노드 교체 시 전부 유실된다.**
> [Phase 5](./phase-05-monitoring-node-rebuild.md)에서 모니터링 노드를 재구축하므로 그 전에 반드시 끝나야 한다.

1. 현재 Grafana UI에서 **대시보드·데이터소스·알림 규칙을 JSON으로 export**
2. `groble-images`에 provisioning 구조로 정리 (`/etc/grafana/provisioning/{datasources,dashboards,alerting}`)
   - Grafana는 아직 `groble-images`에 디렉터리가 없다 — **새로 만들고 CI(`build.yml`)의 paths-filter·matrix에도 등록**해야 한다
3. provisioned 대시보드는 **읽기 전용**으로 설정 (UI 편집분과 코드가 갈라지지 않게)
4. **"기대 타깃 수 미달" 알람 추가** (2-1의 5번에서 이관)
   - 예: `count(up{job="node-exporter"}) < <기대 노드 수>`
   - ⚠️ **기대값을 상수로 박아두면 노드 수를 바꿀 때 알람이 조용히 무의미해진다.**
     provisioning 시 환경별 노드 수 변수에서 주입하거나, 최소한 **"ASG desired 변경 시 함께 바꿀 것" 목록에 등재** (계획서 §2.4)
   - 알림 경로는 Phase 1에서 만든 Slack 2채널(`#groble-alert` / `#groble-alert-dev`)과 정렬한다
5. 새 이미지로 Grafana 서비스 배포

---

## 검증

- [x] **API 태스크 워킹셋 측정·기록** (2-0) — 라이브 셋 최대 prod 510.5 MiB / dev 304.6 MiB
- [ ] Prometheus `/targets`에서 **기존 노드 3대가 모두 UP** — 전환 전 타깃 총 **14개**가 기준값
- [ ] Grafana 대시보드가 프로비저닝으로 복원되었는지, 기존 패널이 정상 렌더되는지
- [ ] `up == 0` 알람과 **"기대 타깃 수 미달" 알람** 동작 확인
- [ ] (Phase 7 진입 전) JVM 수정 배포 후 재측정 → `memoryReservation` 확정

### 전환 전 타깃 기준값 (2026-08-18)

| 잡 | 타깃 수 | 비고 |
|---|---|---|
| node-exporter | 3 | ec2_sd 전환 대상 |
| cadvisor | 3 | ec2_sd 전환 대상 |
| groble-api (spring-apps) | 2 | ALB 경유 유지 |
| prometheus / grafana / loki / otelcol-internal / otelcol-exported / rds-exporter | 각 1 | localhost |
| **합계** | **14** | 전부 UP |

## 롤백

이전 이미지 태그로 서비스 되돌리기. IAM 정책은 남겨둬도 무해하다.

> ⚠️ **이 Phase를 건너뛰고 Phase 7로 가지 않는다.** 새 ASG 노드가 스크레이프되지 않는 상태로 마이그레이션을 진행하면, 문제가 생겨도 지표가 없다.
>
> ⚠️ **JVM 힙 상한 수정 없이 Phase 7로 가지 않는다.** 스왑이 사라지면서 prod API가 OOM kill된다 (2-0 참조).

---

[← Phase 1 — 알람 백스톱 확보](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 — NAT Gateway 전환 →](./phase-03-nat-gateway.md)
