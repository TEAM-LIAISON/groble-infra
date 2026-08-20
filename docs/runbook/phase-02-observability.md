# Phase 2 — 관측 선행 전환 (ASG보다 반드시 먼저)

> [← Phase 1](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 →](./phase-03-nat-gateway.md)

| | |
|---|---|
| **상태** | **진행 중** — 2-0 ✅ · 2-1 ✅ · 2-2 배포 완료(**PR 2건 머지 대기**) |
| **목적** | ASG 도입 후 새 노드가 **관측 사각지대에 들어가는 것을 막는다.** 순서가 뒤바뀌면 노드가 조용히 사라지고, 하필 그 시점이 마이그레이션 중이라 가장 위험하다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 이전 이미지 태그로 롤백 |

---

## 🔖 이어받기 (2026-08-20 기준)

> **다음 세션에서 여기부터 읽으면 된다.** 무엇이 끝났고 무엇이 남았는지, 그리고 순서가 중요한 것.

### 지금 당장 해야 할 일 — 순서 중요

**① `groble-images` PR 2건을 순서대로 머지**

```
#7  fix/slack-message-readability      → main    ← 먼저
#8  feat/payment-success-absence-alerts → #7      ← 그 다음
```

> ⚠️ **순서를 지켜야 한다.** #7 이 알람 임계 단위를 초/바이트 → 시간/MiB 로 바꾼다.
> #8 은 그 위에 쌓여 있다. 뒤집어 머지하면 임계 `93600`(초) 과 시간 단위 값이 어긋나
> **알람이 영영 발화하지 않는다.** 실제로 한 번 그렇게 만들었다가 배포 전 검증에서 잡았다.

**② 머지 후 Grafana 재배포** — 알림 규칙 8건 → 11건

```bash
# 1. CI 가 새 이미지를 push 할 때까지 대기 후 태그 확인
aws ecr describe-images --repository-name groble-grafana --profile groble-terraform \
  --region ap-northeast-2 --query 'reverse(sort_by(imageDetails,&imagePushedAt))[0].imageTags[0]' --output text

# 2. environments/monitoring/images.auto.tfvars 의 grafana_version 갱신 후
cd environments/monitoring && terraform plan   # ← 반드시 검수받고 apply
```

> Grafana 재배포는 **5~6분** 걸린다. 타깃그룹에 `deregistration_delay` 가 없어 기본값 300초를
> 기다린다. 그동안 `monitor.groble.im` 접속 불가.

**③ 배포 후 확인**

```bash
# 알림 규칙 11건, health=ok 인지
curl -s -H "Authorization: Bearer <토큰>" \
  http://10.0.1.193:3000/api/prometheus/grafana/api/v1/rules
```

### 미결 사항 — 사용자 판단 필요

| 건 | 상태 | 필요한 결정 |
|---|---|---|
| **prod JVM 힙 수정 배포** | 백엔드 PR [#826](https://github.com/TEAM-LIAISON/groble-backend/pull/826) 머지됨. **dev 만 배포, prod 미배포** | 백엔드에 재요청 상태. 배포되면 알려주기로 함 → 배포 후 2~3일 재측정하여 Phase 7·8 `memoryReservation` 확정 |
| **`JVM 힙 상한 > 컨테이너 리밋` 알람 발화 중** | prod 미배포 때문. 2시간마다 `#groble-alert` 재전송 | prod 배포되면 자동 해소. 그때까지 감수할지 일시 중지할지 |
| **`컨테이너 메모리 하드리밋 근접` 알람 발화 중** | **dev-mysql 98.8%** (253/256 MiB) · prod-api 92.9% | JVM 을 고쳐도 dev-mysql 때문에 계속 발화한다. **dev MySQL 리밋 256 → 384 MiB 상향 제안** — dev 노드 여유 확인 후 plan 필요 |
| 신규 구독 가입 감시 | 트래픽이 14일에 20건대라 **통계적으로 감지 불가** | 앱 지표(`groble_payment_attempts_total`) 없이는 불가. 백엔드 요청서에 포함됨 |

### 백엔드에 전달된 요청서 2건

| 문서 | 내용 | 상태 |
|---|---|---|
| [`backend-jvm-heap-limit.md`](../handoff/backend-jvm-heap-limit.md) | JVM 힙 상한 `-Xms512m -Xmx900m` 고정 | PR #826 머지, **prod 배포 대기** |
| [`backend-payment-metrics.md`](../handoff/backend-payment-metrics.md) | 대사 불일치·승인 불명·결제 시도 지표 노출 | **전달 여부 미확인** |

결제 알림 정합용 문서를 별도로 만들어 공유했다 (Artifact).

### 현재 배포된 이미지

```
groble-grafana     11.6.3-05735cc      대시보드 3 · 알림 8 (머지 후 11)
groble-prometheus  v2.45.0-143413d     ec2_sd + recording rule 12
groble-loki        3.6.15-c8fcfa0
groble-otelcol     0.132.0-57015e3
```

이미지 태그는 `environments/monitoring/images.auto.tfvars` 에 있고 **git 으로 추적된다**
(`terraform.tfvars` 는 시크릿 때문에 `.gitignore` 대상).

### Phase 2 이후로 넘어가기 전 확인

- [ ] PR #7 → #8 머지 및 Grafana 재배포 (알림 11건)
- [ ] prod JVM 수정 배포 → 2~3일 재측정 → `memoryReservation` 확정 — **Phase 7 차단 조건**
- [ ] dev-mysql 메모리 리밋 결정
- [ ] `spring-apps` 태스크 단위 스크레이프 (Cloud Map) — **Phase 7 로 이관됨**, `desired_count` 2 이상 전에 필수

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

### prod 예상치 — 여유가 60 MiB 수준으로 얇다

dev 컨테이너를 계층별로 분해해 역산했다 (task 1137, 가동 10.4시간 시점).

| 계층 | dev 실측 |
|---|---|
| `container_memory_usage_bytes` (cgroup 총합) | 1,053.6 MiB |
| ├ `container_memory_rss` | 1,032.7 MiB |
| ├ `container_memory_cache` | 15.9 MiB |
| └ 커널 몫 | 약 5 MiB |
| **RSS 내역** — heap committed | **590.0 MiB** (그중 heap used 189.2 / live set 180.8) |
| **RSS 내역** — nonheap committed | 304.4 MiB |
| **RSS 내역** — 네이티브(스레드 스택·다이렉트 버퍼·GC 자료구조·malloc) | 약 138 MiB |

> 📌 `container_memory_usage_bytes` 는 **RSS 가 아니라 `RSS + 페이지 캐시 + 커널 몫`** 이다.
> dev 는 캐시가 16 MiB 뿐이라 RSS 와 거의 같아 보이지만, prod 는 캐시 p99 가 108 MiB 라 차이가 더 벌어진다.
> 또한 **heap committed(590) 와 heap used(189) 는 다르다** — G1 은 한 번 확보한 힙 페이지를 OS 에
> 잘 반납하지 않으므로, 컨테이너가 보는 값은 "실제 사용량"이 아니라 "JVM 이 OS 로부터 잡고 있는 총량"이다.

**prod 환산** — 힙 외 고정분(비힙 + 네이티브)은 dev 에서 `1,032.7 − 590.0 = 442 MiB`.
prod 는 비힙 committed 가 400 MiB 로 dev(304)보다 **96 MiB 크므로 약 538 MiB** 로 본다.
prod 는 라이브 셋(510 MiB)이 커서 힙이 상한 900 MiB 를 거의 다 쓸 것이므로:

> **prod RSS ≈ 900 + 538 = 약 1,440 MiB. 하드리밋 1,500 대비 여유 약 60 MiB.**

⚠️ 이는 초판에 적었던 "1,350~1,380 MiB / 여유 120~150 MiB" 를 대체한다.
초판은 prod 비힙이 dev 보다 크다는 점을 반영하지 않아 낙관적이었다.
**`-Xmx800m` 폴백이 필요할 가능성이 상당하다** (800m 이면 RSS ≈ 1,338 MiB, 여유 약 162 MiB).
prod 배포 직후 RSS 를 우선 확인하고, 1,400 MiB 를 넘어 머물면 즉시 낮춘다.
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
6. ✅ **배포 완료** (2026-08-20) — `v2.45.0-6cbe957` → **`v2.45.0-3c2a266`**, 태스크 정의 rev 23 → 24

   > ✅ **배포 태그를 버전 관리에 편입했다.** `terraform.tfvars` 는 `.gitignore` 의 `*.tfvars` 에
   > 걸려 있어(시크릿 포함) 어떤 이미지가 떠 있는지 git 이력에 남지 않았다. 시크릿이 없는 이미지
   > 식별자만 **`environments/monitoring/images.auto.tfvars`** 로 분리하고 `.gitignore` 에
   > `!images.auto.tfvars` 예외를 뒀다. 분리 후 `terraform plan` 이 **No changes** 임을 확인했다.

   | 서비스 | 배포 태그 | 이전 태그 |
   |---|---|---|
   | Prometheus | `v2.45.0-3c2a266` | `v2.45.0-6cbe957` |

### 배포 후 검증 결과 (2026-08-20)

| 항목 | 결과 |
|---|---|
| 타깃 총계 | **14개 전부 UP** — 전환 전 기준값과 동일 (dropped 0) |
| node-exporter / cAdvisor | 각 **3개**, `ec2_sd` 로 발견 |
| `instance` 라벨 | `10.0.1.193:9100` 등 — **전환 전과 동일** |
| `environment` / `instance_name` | `production`/`groble-prod-instance-1` 등 — **전환 전과 동일** |
| 신규 라벨 | `node_type` / `instance_id`(`i-08b4f8ff…`) / `availability_zone`(`ap-northeast-2a`) 정상 부착 |
| 기존 대시보드 쿼리 | `container_memory_usage_bytes` · `node_memory_*{environment=...}` 등 정상 반환 |
| TSDB 과거 데이터 | **보존됨** (production 노드 15일치 86,391 샘플) |

> 전환 직후 약 5분간 구(static)·신(ec2_sd) 시계열이 병존해 `count(up{job="node-exporter"})` 가 6으로 보였다.
> staleness 창이 지나며 **3으로 정착**했다. 예상된 과도 상태다.

**2-2의 "기대 타깃 수 미달" 알람 기준값**

| 식 | 정상값 |
|---|---|
| `count(up{job="node-exporter"})` | **3** |
| `count(up{job="cadvisor"})` | **3** |
| `count(up == 1)` | **14** |

⚠️ 이 값들은 **노드 수가 바뀌면 함께 바꿔야 한다** (Phase 7 ASG desired 변경 시).

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

## 2-2. Grafana 프로비저닝 as-code ✅ **배포 완료** (머지 대기 2건 있음)

기존 대시보드 4개(전부 커뮤니티 import)를 그대로 옮기지 않고, 수집 중인 지표 2,149개를
전수 조사해 **새로 설계**했다. 인프라 담당자와 백엔드 개발자를 각각 대상으로 한다.

### 배포된 것

| 항목 | 값 |
|---|---|
| Grafana | **11.6.3** (`groble-grafana:11.6.3-05735cc`) — 10.2.0 에서 업그레이드 |
| 대시보드 | **3개** (`groble-overview` · `groble-backend` · `groble-infra`), Groble 폴더, 읽기 전용 |
| 데이터소스 | Prometheus · Loki, **UID 고정**, `readOnly` |
| 알림 규칙 | **8건** 가동 중 (머지 후 11건) |
| 알림 경로 | Grafana → SNS → AWS Chatbot → Slack — **실제 알람으로 도달 검증 완료** |
| recording rules | **12건** (`groble-prometheus:v2.45.0-143413d`) |

기존 UI 대시보드 4개는 General 폴더에 그대로 남아 있다(SQLite 마이그레이션 후에도 보존됨).
정리 여부는 새 대시보드를 써본 뒤 팀이 정하면 된다.

### Grafana 11.x 로 올린 이유

**네이티브 AWS SNS contact point 가 11.x 부터 있다.** 10.2 에는 없어 Slack Webhook 을 새로
발급해야 했고, 그러면 시크릿이 하나 는다. 11.6.3 으로 올려 **Phase 1 이 만든 SNS→Chatbot→Slack
경로를 그대로 재사용**했다 — 새 시크릿이 하나도 생기지 않았다.

> ⚠️ **10.2 로의 롤백은 불가능하다.** Grafana 11 이 기동 시 SQLite 스키마를 단방향
> 마이그레이션한다. 대시보드·데이터소스·알림이 모두 이미지에 있으므로, 최악의 경우
> `/opt/grafana/data/grafana.db` 를 지우고 새로 시작하면 된다(사용자 계정과 기존 UI
> 대시보드 4개는 잃는다). 백업 없이 진행하기로 합의했다.

> ⚠️ `grafana-simple-json-datasource` 를 `grafana_plugins` 에서 제거했다. Angular 플러그인이라
> 11.x 에서 **다운로드는 되지만 조용히 로드되지 않는다.** 쓰이지 않던 플러그인이다.

### 설계에서 지킨 것

**조회 비용을 고정했다.** `http_server_requests_seconds_bucket` 은 17,457 시계열로 전체
TSDB 의 43% 다. 대시보드에서 `histogram_quantile` 을 직접 돌리면 Prometheus(512 MiB 하드리밋,
유휴 340 MiB)가 **OOM 으로 죽는다 — 실제로 그렇게 죽인 적이 있다.** recording rule 로 미리
계산해 `p95` 조회가 17,457개가 아니라 **2개 시계열**만 읽는다. CI 검증기가 원본 버킷을
직접 집계하는 쿼리를 아예 차단한다.

**임계는 전부 실측 기준선에서 왔다.** p95 81ms → 경고 300ms, 5xx 0.0003% → 경고 0.5% 등.

**이 서비스에만 있는 것을 넣었다.** `groble_scheduled_last_completed_timestamp_seconds` 로
결제·정산 배치의 마지막 성공 경과를 본다. 배치가 조용히 멈춰도 자원 그래프는 멀쩡하다.

### 알림 규칙 (머지 후 11건)

CloudWatch 알람 19건(Phase 1)이 ALB·RDS 를 이미 덮으므로 **중복하지 않는다.**
아래는 CloudWatch 가 구조적으로 볼 수 없는 것들이다.

| 규칙 | 임계 | severity | 근거 |
|---|---|---|---|
| Prometheus 기대 타깃 수 미달 | < 3개, 10분 | critical | `ec2_sd` 고장 시 타깃이 목록에서 **사라져** `up==0` 으로 안 잡힘 |
| 스크레이프 타깃 다운 | > 0개, 10분 | warning | — |
| **결제 경로 서버 오류(5xx)** | 15분 1건, 즉시 | critical | 7일간 5xx **0건** |
| **결제 성공 부재** | 2시간 0건 | critical | 14일간 시간당 최저 15건(06시) |
| **정기결제·정산 배치 정체** | **25시간** | critical | 주기 24.00h 고정시각 + 1h → 예정 시각 +1h 감지 |
| 주기 배치 정체 (6시간 이하) | 9시간 | warning | 최장 주기 6h + 여유 |
| 결제 실패 급증 | 15분 20건 | warning | p50 0 / p90 1 / p99 8, 20+ 는 7일 2회 |
| 컨테이너 메모리 하드리밋 근접 | > 90% | warning | ECS `MemoryUtilization` 은 캐시를 합쳐 보여줌 |
| 노드 스왑 | > 300 MiB | warning | CloudWatch 는 EC2 스왑을 수집 안 함. **Phase 7 차단 조건** |
| JVM 힙 상한 > 컨테이너 리밋 | > 0 MiB | critical | 2026-08 사고의 **원인 자체**를 감시 |
| API 응답 지연 (앱 레벨 p99) | 3초, 5분 | warning | ALB p99(CloudWatch)와 달리 앱 내부 시간 |

`critical` → `#groble-alert`, `warning` → `#groble-alert-dev`.
각 규칙의 `annotations.runbook` 에 대응 절차가 있고 Slack 알림에 함께 실린다.
**검증기가 `runbook` 이 없는 규칙을 거부한다** — 받은 사람이 무엇을 할지 모르면 소음이다.

### 배포하며 겪은 함정 (재발 방지 장치 포함)

| 함정 | 증상 | 현재 방어 |
|---|---|---|
| 대시보드를 `/var/lib/grafana` 에 구움 | ECS 가 호스트 볼륨을 거기 마운트해 **가려짐** | 검증기가 provider 경로 검사 |
| 데이터소스 UID 불일치 | 기존 대시보드 100곳이 `Datasource not found` | 검증기가 UID 대조 |
| 미정의 recording rule 참조 | **오류 없이 빈 그래프** — 가장 알아채기 어려움 | 검증기가 rule 이름 대조 |
| 분모에 `clamp_min` | 리밋 없는 컨테이너에서 **6,632,243,200%** | 검증기가 `clamp_min` 분모 거부 |
| SNS 메시지 JSON 깨짐 | **Chatbot 이 조용히 버림** — 알람이 아예 안 옴 | 검증기가 실제 annotation 으로 JSON 파싱 검증 |
| Slack 볼드 `**` | 별표가 그대로 노출 (mrkdwn 은 `*` 하나) | 검증기가 `**` 거부 |
| 지표 단위와 임계 불일치 | 임계 93600(초) vs 값 5(시간) → **영영 발화 안 함** | 배포 전 쿼리 평가로 확인 |


---

## 검증

- [x] **API 태스크 워킹셋 측정·기록** (2-0) — 라이브 셋 최대 prod 510.5 MiB / dev 304.6 MiB
- [x] Prometheus `/targets`에서 **노드 3대 모두 UP** — 타깃 총 **14개**, 전환 전과 동일
- [x] Grafana 대시보드가 프로비저닝으로 복원 — Groble 폴더 3개, 읽기 전용 강제 확인
- [x] `up == 0` 알람과 **"기대 타깃 수 미달" 알람** 동작 확인 (health=ok)
- [x] **Slack 도달 검증** — JVM 힙 알람이 실제로 `#groble-alert` 에 도달
- [ ] PR #7 → #8 머지 후 Grafana 재배포 → 알림 **11건** 확인
- [ ] (Phase 7 진입 전) **prod** JVM 수정 배포 후 재측정 → `memoryReservation` 확정

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
