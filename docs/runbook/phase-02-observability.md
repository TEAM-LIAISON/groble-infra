# Phase 2 — 관측 선행 전환 (ASG보다 반드시 먼저)

> [← Phase 1](./phase-01-alarm-backstop.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 3 →](./phase-03-nat-gateway.md)

| | |
|---|---|
| **상태** | 🔄 진행 중 — 배포·검증 완료 (2026-08-24), **백엔드 회신 대기 2건**. `memoryReservation` 확정으로 **Phase 7 차단 해제.** 남은 것은 ① 죽은 JVM 힙 알람 수정 ② 백엔드 지표 후 R10~R14 |
| **목적** | ASG 도입 후 새 노드가 **관측 사각지대에 들어가는 것을 막는다.** 순서가 뒤바뀌면 노드가 조용히 사라지고, 하필 그 시점이 마이그레이션 중이라 가장 위험하다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 이전 이미지 태그로 롤백 |

---

## 🔖 이어받기 (2026-08-20 기준)

> **다음 세션에서 여기부터 읽으면 된다.** 무엇이 끝났고 무엇이 남았는지, 그리고 순서가 중요한 것.

### 지금 당장 해야 할 일

> ✅ **결제 알림은 끝났다.** 백엔드 확정 설계를 받아 R1~R9 로 전면 교체하고 배포·도달 검증까지 마쳤다.
> **더 이상 지금 할 수 있는 작업이 없다** — 남은 3건은 전부 기다려야 하는 것이다. 아래 [완료 조건](#phase-2-완료-조건).

**① ✅ 완료 — 결제 알림 R1~R9 배포** (2026-08-20)

백엔드가 검수 회신 대신 **확정 설계**(`2026-08-20-payment-monitoring-alert-design.md`)를 보내와
그대로 반영했다. 알림 규칙 **8건 → 14건**.

가장 중요한 답은 **Q6 이었다 — `GET /api/v1/content/{contentId}/pay` 는 결제 화면 조회다.**
기존 `결제 성공 부재` 는 이 값을 세고 있었으므로 **PG 승인이 전부 실패해도 줄지 않는다.**
신호를 둘로 교체했다.

| 신호 | 뜻 |
|---|---|
| `GET /api/v1/orders/success/{merchantUid}` 200 | 주문이 PAID 일 때만 200 → **결제 완료** |
| 페이플 승인 창구 2곳 도달(200/302) | **결제 시도** |

합쳐 보면 활동 부재(R2), 갈라 보면 시도 대비 완료 부재(R3)다. R3 은 트래픽은 정상인데
승인만 전멸하는 상태를 잡으며 기존 규칙 어느 것도 보지 못하던 각도다.

| 규칙 | 임계 | 등급 |
|---|---|---|
| R1 결제 경로 5xx | > 0건 / 15분 | critical |
| R2 결제 활동 부재 | < 1건 / 6시간 | critical |
| R3 시도는 있는데 완료가 없다 | 3시간 시도 8건+ & 완료 0 | critical |
| R4 결제 실패 급증 | > 20건 / 15분 | warning |
| R5 핵심 경로 p99 | > 5초 | critical |
| R6 일 1회 배치 정체 | > 25시간 | critical |
| R7 단주기 배치 정체 | > 9시간 | warning |
| R8 웹훅 재시도 정체 | > 30분 | warning |
| R9 배치가 시작만 하고 미완료 | 격차 > 1시간 | warning |

**설계안에서 바꾼 것 2가지** ([groble-images#9](https://github.com/TEAM-LIAISON/groble-images/pull/9))

- **모든 식에 `environment="production"` 추가.** 설계안은 중복 집계 방지로 `job="groble-api"` 만
  걸었으나 **이 job 에는 dev 와 prod 가 함께 들어 있다.** 그대로 두면 dev 로 결제 알람이 울리고,
  R6~R8 의 `and on() (... process_start_time_seconds ...)` 는 우변이 2개 시계열이 되어
  `duplicate series for match group {}` 로 **쿼리 자체가 에러**가 된다.
  검증기에 검사를 넣었고, 환경 무관이 의도인 규칙은 `labels.scope: fleet` 로 명시한다.
- **배치 정체는 2분기식 대신 `clamp_max` 단일식.** 의미는 같으면서 값이 시간 단위 하나로 나와
  Slack 에 `{{ $labels.job_id }} 가 N.N시간째` 로 실린다. `and on()` 매칭 함정도 피한다.

R5 는 recording rule `groble:critical_path_duration_seconds:p99` 로 분리했다 —
셀렉터가 좁아 966 시계열(전체 버킷 12,489 의 7.7%)이지만 알림은 1분마다 평가되므로
대시보드보다 잦다. 검증기의 버킷 직접 참조 금지 검사도 알림 규칙까지 확장했다.

**백엔드 요청 검증 2건** (8/17 18:15 이후 정상 구간)

| | 결과 | 판정 |
|---|---|---|
| V1 — R2 창 크기 | **18.01** | ≥ 1 → `[6h]` 유지 |
| V2 — R4 임계 | **5.08** | < 20 → 임계 20 유지 |

**②  ⚠️ 배포하며 겪은 것 — Grafana 는 파일에서 지운 규칙을 삭제하지 않는다**

① 배포 직후 **파일에는 14건인데 Grafana 는 15건**을 로드하고 있었다.
`rules.yaml` 에서 제거한 `groble-batch-stalled` 가 노드 로컬 SQLite 에 남아 계속 평가된 것이다.

남은 규칙은 옛 단식(`(max(time() - gauge)) / 3600 > 26`)이었고, 하필 prod 가 JVM 힙 수정으로
재배포되며 gauge 가 0 인 배치가 8개가 되어 **496,448 시간(=56년)으로 계산돼 `#groble-alert` 로
발화하고 있었다.** ①이 `clamp_max` 로 고친 바로 그 결함이 지웠다고 생각한 규칙에서 되살아난 것이다.

→ **`deleteRules` 에 uid 를 명시해야 지워진다** ([groble-images#10](https://github.com/TEAM-LIAISON/groble-images/pull/10)).
검증기에 정합성 검사를 넣었고 `rules.yaml` 상단에 사고 경위와 함께 규칙을 적었다.

> 🔴 **다음에 규칙을 제거할 때 반드시 기억할 것.** 검증기는 uid 가 조용히 사라지는 것을
> 잡지 못한다 — 이전 리비전을 모르기 때문이다.

**배포 후 검증** (2026-08-20)

| 항목 | 결과 |
|---|---|
| 실행 이미지 | `groble-grafana:11.6.3-d1ac4d3` (태스크 정의 rev 49) |
| 알림 규칙 | **14건** `state=active` |
| 평가 실패 | **0건** |
| 신규 일 1회 배치 규칙 | 7개 시계열, 최대 **2.07시간** (임계 25) — 정상 |
| 같은 시점 옛 규칙이었다면 | 496,448시간 → 발화 |

마지막 줄이 이 교체의 값어치다. **prod 재배포 2시간 뒤인 지금, 옛 규칙은 오발화하고 신규 규칙은 조용하다.**

**③ ✅ 알림 경로 도달 검증** (2026-08-20)

두 SNS 토픽에 Chatbot custom notification 형식으로 테스트 메시지를 직접 발행해
**Slack 양쪽 채널에서 눈으로 도달을 확인**했다.

| 채널 | 토픽 | MessageId |
|---|---|---|
| `#groble-alert` (critical) | `groble-alerts-prod` | `183ca241-bd54-5a7c-95f5-c14106518c99` |
| `#groble-alert-dev` (warning) | `groble-alerts-dev` | `785d9b4e-9e8f-59b0-881c-f84e25845cb2` |

```bash
aws sns publish --topic-arn <토픽> --subject "[TEST] 알림 경로 도달 확인" \
  --message file://<Chatbot custom notification JSON> \
  --profile groble-terraform --region ap-northeast-2
```

> ⚠️ **SNS 가 MessageId 를 돌려줬다는 것과 Slack 에 보였다는 것은 다르다.**
> AWS Chatbot 은 스키마가 맞지 않으면 **조용히 버리는데, 그때도 SNS 쪽은 성공으로 보인다.**
> 반드시 Slack 화면을 직접 볼 것. `contact-points.yaml` 과 같은 `version`/`source`/`content`
> 스키마를 쓰고, 볼드는 별표 **하나**(mrkdwn)여야 한다.

**이 방식이 검증하는 것과 못 하는 것**

- ✅ SNS 토픽 → Chatbot 구독 → Slack 채널 매핑 (토픽마다 다르므로 실제로 갈릴 수 있는 부분)
- ❌ Grafana 의 알림 템플릿 렌더링 — 다만 이건 같은 날 **실제 알람으로 이미 증명됐다**
  (critical: 옛 배치 규칙 오발화 · warning: `컨테이너 메모리 하드리밋 근접` dev-mysql 99.2%)

임계를 임시로 낮춰 실제 발화시키는 방법이 전 경로를 한 번에 검증하지만,
**배포 2회 × 7분 = 약 14분 중단**이 든다. 위 두 가지가 이미 각각 증명돼 있어 그 비용을 쓰지 않았다.

### 미결 사항 — 사용자 판단 필요

| 건 | 상태 | 필요한 결정 |
|---|---|---|
| **prod JVM 힙 수정 배포** | ✅ **완료** (2026-08-20). 힙 상한 2,878 → **900 MiB** 확인 | 남은 것은 **2~3일 뒤 재측정**뿐이다 → Phase 7·8 `memoryReservation` 확정. **Phase 7 차단 조건** |
| **`JVM 힙 상한 > 컨테이너 리밋` 알람** | ✅ **해소.** prod 배포로 900 MiB < 리밋 1,500 MiB 가 되어 조건이 성립하지 않는다 | 없음 |
| **`컨테이너 메모리 하드리밋 근접` 알람 발화 중** | **dev-mysql 99.1%** (253.8/256 MiB) · prod-api 92.9% | ✅ **결정됨 — 상향하지 않는다.** [Phase 8](./phase-08-dev-migration.md) 에서 dev MySQL 이 RDS 로 이관되며 컨테이너째 사라지므로 그때까지 발화를 감수한다. 조사 결과(재시작 5회 증거 · `ignore_changes` 함정 · 무효한 `MYSQL_INNODB_BUFFER_POOL_SIZE`)는 Phase 8 문서에 기록했다 |
| 신규 구독 가입 감시 | 트래픽이 14일에 20건대라 **통계적으로 감지 불가** | 앱 지표(`groble.payment.attempts`) 없이는 불가. 요청서 §6-3 ③ 에 포함됨 |

### 백엔드 요청서 2건

| 문서 | 내용 | 상태 |
|---|---|---|
| [`backend-jvm-heap-limit.md`](../handoff/closed/backend-jvm-heap-limit.md) | JVM 힙 상한 `-Xms512m -Xmx900m` 고정 | ✅ **완료** — PR #826 머지, dev·prod 배포 완료 |
| [`payment-alerts-review.md`](../handoff/payment-alerts-review.md) | **A** 결제 알림 5건 검수(Q1~Q12) + **B** 지표 3종 노출 요청 | **A ✅ 회신 완료** → R1~R9 로 반영·배포. **B 는 대기** — 지표 3종이 나오면 R10~R14 를 건다 |

> 지표 요청서(`backend-payment-metrics.md`)는 별도 문서였으나, 백엔드에 문서를 둘로 던지지 않으려고
> **검수 요청서의 §6 으로 흡수하고 삭제했다.** 기준선도 7일 → **14일로 통일**했다.

### 현재 배포된 이미지

```
groble-grafana     11.6.3-d1ac4d3      대시보드 3 · 알림 14 (결제 R1~R9 포함)
groble-prometheus  v2.45.0-3ea416e     ec2_sd + recording rule 13
groble-loki        3.6.15-c8fcfa0
groble-otelcol     0.132.0-57015e3
```

이미지 태그는 `environments/monitoring/terraform.tfvars` 에 있다.
⚠️ 이 파일은 `.gitignore` 대상이라 **배포 태그가 git 이력에 남지 않는다** — 태그를 바꿀 때
주석으로 이전 값을 남길 것 (2026-08-20 에 `images.auto.tfvars` 를 없애고 합쳤다).

### Phase 2 완료 조건 — **2026-08-24 시점: 대기 2건 모두 통과**

| 항목 | 결과 |
|---|---|
| **R6~R9 오탐 없음** (배포 후 4일) | ✅ **오탐 0건** — 아래 [배치 규칙 4일 검증](#배치-규칙-4일-검증-2026-08-24) |
| **prod 재측정** → `memoryReservation` | ✅ **확정** — 아래 [prod 재측정](#prod-재측정-2026-08-24--memoryreservation-확정). 🔓 **[Phase 7](./phase-07-prod-asg.md) 차단 해제** |
| **R10~R14** (백엔드 지표 3종) | ⏸ 백엔드 대기. Phase 2 완료를 막지 않는다 — [요청서](../handoff/payment-alerts-review.md) §6 |

> 🔴 **다만 검증 중 죽은 알람 1건을 발견했다** — 아래 [JVM 힙 알람이 NoData 로 죽어 있다](#-jvm-힙-알람이-nodata-로-죽어-있다-2026-08-24).
> Phase 2 를 닫기 전에 고쳐야 한다.

**Phase 3~6 은 지금 시작해도 된다.** Phase 2 의 목적("ASG 도입 전에 관측 사각지대를 없앤다")은
노드 스크레이프가 `ec2_sd` 로 바뀌고 알림 14건이 가동되면서 달성됐다.

---

### 배치 규칙 4일 검증 (2026-08-24)

배포 직후 오발화가 **기존 규칙의 최대 결함**이었으므로, 일 1회 배치가 실제로 여러 바퀴 도는 것을 보고 확정했다.

| 규칙 | 4일간 최대 | 임계 | 결과 |
|---|---|---|---|
| R6 일 1회 배치 정체 | **24.00시간** | 25 | ✅ 오탐 0 |
| R7 단주기 배치 정체 | **6.00시간** | 9 | ✅ 오탐 0 |
| R8 웹훅 재시도 정체 | 0.08시간 | 0.5 | ✅ 오탐 0 |
| R9 배치 시작만 하고 미완료 | 0.00시간 | 1 | ✅ 오탐 0 |

**숫자가 설계를 그대로 확인해 준다.** R6 의 최대가 정확히 **24.00시간**인 것은 일 1회 배치가
다음 실행 직전에 도달하는 값이고, R7 의 **6.00시간**은 최장 주기 배치의 주기 그 자체다.

> ⚠️ **R6 의 여유는 1시간뿐이다** (24.00 → 임계 25). 이는 "예정 시각 +1h 에 감지"라는 의도된
> 설계지만, **배치가 1시간 넘게 지연되면 곧바로 critical 이 뜬다.** 지연이 잦아지면
> 임계를 26 으로 올리기보다 지연 원인을 봐야 한다 — 스케줄러 스레드풀이 1개라 앞 배치에 밀린다(R8 참조).

---

### prod 재측정 (2026-08-24) — `memoryReservation` 확정

JVM 힙 수정(`-Xms512m -Xmx900m`) 배포 후 4일, 5분 해상도.

| 항목 | 수정 전 (15일) | 배포 직후 예상 | **수정 후 (4일)** |
|---|---|---|---|
| 컨테이너 RSS p50 / p90 / p99 / 최대 | 1,274 / 1,484 / — / 1,493 | ≈1,440 | **1,188 / 1,264 / 1,281 / 1,290 MiB** |
| 컨테이너 usage 최대 | — | — | 1,473 MiB (리밋 1,500) |
| heap committed 최대 | 1,766 MiB | 900 | **731 MiB** — 상한 900 을 다 쓰지 않는다 |
| heap used p99 | 1,362 MiB | — | 682 MiB |
| live set 최대 | 510.5 MiB | — | 210 MiB |
| nonheap committed 최대 | 400 MiB | 400 | **401 MiB** — 예상과 일치 |
| **GC 최대 pause** | **2,584 ms** | — | **73 ms** |
| **노드 스왑 사용 최대** | **947 MiB** | — | **64 MiB** |
| 노드 `MemAvailable` 최소 | 365 MiB | — | **910 MiB** |

**예상보다 낫다.** 배포 직후 적어 둔 "RSS ≈ 1,440 MiB, 여유 60 MiB, `-Xmx800m` 폴백이 필요할
가능성이 상당하다"는 **기우였다.** 실측 최대는 1,290 MiB 로 하드리밋 1,500 대비 **여유 210 MiB** 다.
→ **`-Xmx800m` 폴백은 필요 없다.**

GC 최대 정지가 **2,584 ms → 73 ms (35배 개선)**, 스왑이 947 → 64 MiB 로 떨어진 것이
이 수정의 실제 효과다. JVM 힙이 디스크에 밀려 있던 상태가 해소됐다.

#### 확정값

| 대상 | 값 | 근거 |
|---|---|---|
| [Phase 7](./phase-07-prod-asg.md) prod `memory_reservation` | **1,300 MiB** | RSS p99 1,281 · 최대 1,290 을 덮는 최소값 |
| prod `memory` (하드리밋) | **1,500 MiB 유지** | 여유 210 MiB. 상향 불필요 |
| [Phase 8](./phase-08-dev-migration.md) dev `memory_reservation` / `memory` | **prod 와 동일** | dev RSS p99 **1,277** · 최대 **1,287 MiB** — prod 와 사실상 같다 |

> 📌 **dev 가 prod 보다 작을 것이라던 이전 가정은 폐기한다.** dev live set 은 356 MiB 로
> prod(210)보다 오히려 크고, RSS 는 양쪽 다 1,280 MiB 대다.
> **둘 다 `-Xmx900m` 이므로 RSS 는 라이브 셋이 아니라 힙 상한이 결정한다** —
> G1 은 한 번 확보한 힙을 OS 에 잘 반납하지 않는다. 사이징은 `-Xmx` 를 보고 하면 된다.

**t3.medium 노드당 태스크 2개 수용**: 2 × 1,300 = 2,600 MiB + 노드 오버헤드(ECS 에이전트 ·
node-exporter · cAdvisor ≈ 400~500) ≈ 3,100 MiB < 3,837 MiB. **수용 가능하다.**
어차피 **ENI 3개 제약으로 노드당 awsvpc 태스크는 최대 2개**가 상한이다.

---

### 🔴 JVM 힙 알람이 NoData 로 죽어 있다 (2026-08-24)

재측정 중 발견했다. **`jvm_memory_max_bytes{id="G1 Old Gen"}` 시계열이 더 이상 존재하지 않는다.**

```
max by (environment) (jvm_memory_max_bytes{job="groble-api",id="G1 Old Gen"})  → {}  (빈 결과)
sum by (environment) (jvm_memory_max_bytes{job="groble-api",area="heap"})      → 870 MiB (dev·prod)
```

`groble-backend` 대시보드는 `dda22ff`(2026-08-24)에서 `sum(area="heap")` 으로 고쳤으나,
**같은 쿼리를 쓰는 알림 규칙 `groble-jvm-heap-exceeds-container` 는 고쳐지지 않았다.**

```yaml
expr: (max(jvm_memory_max_bytes{job="groble-api",id="G1 Old Gen"}) - min(...)) / 1048576
noDataState: OK        # ← 빈 결과가 조용히 OK 로 처리된다
```

> **이 알람은 2026-08 사고의 원인 자체를 감시하는 규칙인데, 지금은 어떤 오설정에도 울리지 않는다.**
> 런북의 함정 표에 적어 둔 *"오류 없이 빈 그래프 — 가장 알아채기 어려움"* 이 알림 규칙에서 재현된 것이다.

**고칠 것 2가지**

1. `expr` 을 `sum by (environment) (jvm_memory_max_bytes{...,area="heap"})` 로 교체
   (대시보드와 같은 식. 단 알람은 환경별로 비교해야 하므로 `by (environment)` 필요)
2. `noDataState` 를 `OK` → **`Alerting`** 으로. 이 규칙에서 NoData 는 정상이 아니라
   **지표가 사라졌다는 뜻**이고, 그것 자체가 알아야 할 사건이다

> 💡 **재발 방지**: 검증기가 "알림 규칙이 참조하는 시계열이 실제로 존재하는가"를 확인하지 못한다.
> CI 는 운영 Prometheus 에 접근할 수 없으므로 구조적으로 어렵다. 대안은 **배포 후 각 규칙의
> 쿼리를 한 번 평가해 빈 결과를 보고하는 절차**이며, 이 세션에서 수동으로 하던 것을 스크립트화할 만하다.

### 상세 체크리스트

- [x] 백엔드 결제 알림 검수 회신 → **확정 설계 수령, R1~R9 로 전면 교체**
- [x] 모든 HTTP 식에 `method!="OPTIONS"` 반영 (CORS preflight 오집계)
- [x] PR #7 머지 및 Grafana 재배포 (rev 47, 알림 8건)
- [x] PR #9 머지 및 Grafana·Prometheus 재배포 (rev 48, 알림 14건)
- [x] PR #10 머지 및 Grafana 재배포 (rev 49, `deleteRules` 로 옛 규칙 실제 삭제)
- [x] **R6~R9 오탐 없음 확인** (2026-08-24, 4일치) — 최대 R6 24.00h / R7 6.00h, 오탐 0건
- [x] Slack 두 채널 테스트 발화 — **양쪽 도달 확인** (2026-08-20, 아래 「알림 경로 도달 검증」)
- [ ] 백엔드 지표 3종 배포에 맞춰 **R10~R14** 반영
- [x] prod JVM 수정 배포 (2026-08-20, 힙 상한 900 MiB 확인)
- [x] prod 재측정 → **`memory_reservation` = 1,300 MiB 확정** (2026-08-24) — Phase 7 차단 해제
- [ ] 🔴 **JVM 힙 알람 수정** — `id="G1 Old Gen"` 시계열 소멸로 NoData(=OK) 상태. 어떤 오설정에도 안 울린다
- [x] dev-mysql 메모리 리밋 결정 — **상향하지 않고 [Phase 8](./phase-08-dev-migration.md) 이관에 맡긴다**
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
| [Phase 7](./phase-07-prod-asg.md) `memory_reservation` | ✅ **1,300 MiB 확정** (2026-08-24 재측정, RSS p99 1,281 / 최대 1,290) |
| [Phase 8](./phase-08-dev-migration.md) dev `memory` | ✅ **prod 와 동일** (dev RSS p99 1,277 / 최대 1,287). 둘 다 `-Xmx900m` 이라 RSS 는 라이브 셋이 아니라 힙 상한이 결정한다 |
| t3.medium 노드당 태스크 2개 수용 | 수용 가능할 전망 (2 × ~1,300 MiB + 노드 오버헤드 < 3,837 MiB). 어차피 **ENI 3개 제약으로 노드당 awsvpc 태스크는 최대 2개**가 상한이다 |

### ⚠️ Phase 7 차단 조건

**지금 OOM을 막고 있는 스왑파일은 AMI 기능이 아니라 현재 노드의 `user_data`가 만드는 것이다.**
[Phase 7](./phase-07-prod-asg.md)에서 노드가 ECS-optimized AL2023 AMI + Launch Template으로 교체되면 이 스왑은 사라진다.

> **JVM 설정을 그대로 둔 채 노드를 교체하면 새 ASG 노드에서 prod API가 OOM kill로 종료된다.**
> 하필 마이그레이션 도중이라 원인 판별이 가장 어려운 시점이다.

### 후속 조치

`groble-backend`는 별도 레포이므로 **작업 요청서**를 작성해 전달했다 —
[`docs/handoff/closed/backend-jvm-heap-limit.md`](../handoff/closed/backend-jvm-heap-limit.md)

- [x] 백엔드 Dockerfile 수정 — [groble-backend#826](https://github.com/TEAM-LIAISON/groble-backend/pull/826) 머지 (2026-08-19, `2f7ab40`).
      요청서의 **방식 A**(Dockerfile 직접 고정) 채택: `-Xms512m -Xmx900m -XX:+ExitOnOutOfMemoryError`
- [x] **dev 배포 완료** — 아래 검증 결과 참조
- [x] **prod 배포 완료** (2026-08-20) — 아래 「prod 배포 직후 관측」 참조
- [x] prod 배포 후 재측정 완료 (2026-08-24) → `memory_reservation` **1,300 MiB** 확정

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

### prod 배포 직후 관측 (2026-08-20, 가동 21분 시점)

**예상보다 낫다. 하지만 21분은 판단하기에 너무 이르다.**

| 항목 | 수정 전 (15일) | 예상치 | **수정 후 (21분)** |
|---|---|---|---|
| JVM 힙 상한 | 2,878 MiB | 900 | **900 MiB** |
| heap committed | max 1,766 MiB | — | **645 MiB** |
| heap used | p99 1,362 MiB | — | 455 MiB |
| live set | max 510.5 MiB | — | 251 MiB |
| nonheap committed | 400 MiB | 400 | **285 MiB** |
| **컨테이너 RSS** | max 1,493 MiB | **≈1,440** | **1,059 MiB** |
| 컨테이너 usage / 리밋 | — | — | 1,092 / 1,500 MiB |
| **노드 스왑 사용** | max 947 MiB | — | **64 MiB** |

`JVM 힙 상한 > 컨테이너 리밋` 알람은 조건이 성립하지 않아 **해소됐다** (900 < 1,500).

⚠️ **이 값으로 `memoryReservation` 을 확정하면 안 된다.** 세 가지 이유가 있다.

1. **21분은 워밍업 구간이다.** live set 이 251 MiB 로 15일 최대(510.5)의 절반이다 —
   캐시·커넥션풀·클래스로딩이 아직 안 찼다
2. **G1 은 힙을 필요할 때 늘린다.** committed 645 MiB 는 상한 900 을 다 쓴 값이 아니다.
   부하가 오르면 900 까지 커밋되고, 그만큼 RSS 가 올라간다
3. **nonheap 285 MiB 는 dev(304)보다도 작다.** 예상치의 근거였던 prod nonheap 400 MiB 에
   아직 도달하지 않았다

예상식(`900 + 538 = 1,440`)이 틀렸다는 뜻이 아니라 **아직 검증되지 않았다**는 뜻이다.
**2~3일 뒤 재측정에서 RSS p99 를 보고 확정한다.** 그때까지 1,400 MiB 를 넘어 머물면 `-Xmx800m` 으로 낮춘다.
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
   | 모니터링(구) | `groble-nat-instance` ※ | `monitoring` | `Monitoring` | `groble-cluster` | 10.0.1.193 |
   | 운영 | `groble-prod-instance-1` | `production` | `Production` | `groble-cluster` | 10.0.11.62 |
   | 개발 | `groble-develop-instance` | `development` | `Development` | `groble-cluster` | 10.0.12.215 |
   | 모니터링(신) | `groble-monitoring-v2-instance` | `monitoring` | `Monitoring` | `groble-cluster` | 10.0.12.100 |

   > ※ 구 모니터링 노드는 2026-08-30 [Phase 4](./phase-04-monitoring-node-rebuild.md) 에서
   > `groble-monitoring-instance` → `groble-nat-instance` 로 개명했다(태그만 변경, 재기동 없음).
   > 관측 스택이 신 노드로 옮겨가면 이 노드에는 NAT·bastion·WireGuard 만 남기 때문이다.
   > **Prometheus 가 Name 태그를 `instance_name` 라벨로 승격하므로 그 시점에 해당 노드의
   > 시계열이 끊긴다** — 규칙 의존은 0건이고 대시보드 연속성에만 영향이다.

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

   > 📌 이때 배포 태그를 추적하려고 `images.auto.tfvars` 로 분리했었으나,
   > **2026-08-20 에 `terraform.tfvars` 로 다시 합쳤다** (파일이 둘로 갈리는 것을 피하려고).
   > 합친 뒤 `terraform plan` 이 **No changes** 임을 확인했다. 지금은 배포 태그가 git 에
   > 남지 않으므로 태그 변경 시 주석으로 이전 값을 남긴다.

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

## 2-2. Grafana 프로비저닝 as-code ✅ **배포 완료**

기존 대시보드 4개(전부 커뮤니티 import)를 그대로 옮기지 않고, 수집 중인 지표 2,149개를
전수 조사해 **새로 설계**했다. 인프라 담당자와 백엔드 개발자를 각각 대상으로 한다.

### 배포된 것

| 항목 | 값 |
|---|---|
| Grafana | **11.6.3** (`groble-grafana:11.6.3-676e2ff`) — 10.2.0 에서 업그레이드 |
| 대시보드 | **3개** (`groble-overview` · `groble-backend` · `groble-infra`), Groble 폴더, 읽기 전용 |
| 데이터소스 | Prometheus · Loki, **UID 고정**, `readOnly` |
| 알림 규칙 | **14건** 가동 중 (결제 R1~R9 포함) |
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

### 알림 규칙 14건

CloudWatch 알람 19건(Phase 1)이 ALB·RDS 를 이미 덮으므로 **중복하지 않는다.**
아래는 CloudWatch 가 구조적으로 볼 수 없는 것들이다.

| 규칙 | 임계 | severity | 근거 |
|---|---|---|---|
| Prometheus 기대 타깃 수 미달 | < 3개, 10분 | critical | `ec2_sd` 고장 시 타깃이 목록에서 **사라져** `up==0` 으로 안 잡힘 |
| 스크레이프 타깃 다운 | > 0개, 10분 | warning | — |
| 컨테이너 메모리 하드리밋 근접 | > 90% | warning | ECS `MemoryUtilization` 은 캐시를 합쳐 보여줌 |
| 노드 스왑 | > 300 MiB | warning | CloudWatch 는 EC2 스왑을 수집 안 함. **Phase 7 차단 조건** |
| JVM 힙 상한 > 컨테이너 리밋 | > 0 MiB | critical | 2026-08 사고의 **원인 자체**를 감시. `labels.scope: fleet` (환경 무관) |
| **R1 결제 경로 서버 오류(5xx)** | 15분 1건, 즉시 | critical | 60.9시간 175,977 요청 중 5xx **0건** |
| **R2 결제 활동 부재** | 6시간 0건, 30분 | critical | 완료 + 시도 합계가 시간당 약 12건. V1 검증 최소 **18건** |
| **R3 시도는 있는데 완료가 없다** | 3시간 시도 8건+ & 완료 0, 15분 | critical | 승인 전건 거절을 잡는다. **기존 규칙이 못 보던 각도** |
| **R4 결제 실패 급증** | 15분 20건, 5분 | warning | 410·401·완료페이지 400 제외 후 V2 검증 최대 **5.08건** |
| **R5 핵심 경로 응답 지연 (p99)** | 5초, 5분 | critical | 느린 200 만 쌓이는 장애(8/13)는 5xx 로 안 잡힘. recording rule 사용 |
| **R6 일 1회 배치 정체** | 25시간, 15분 | critical | 주기 24h + 1h → 예정 시각 +1h 감지 |
| **R7 단주기 배치 정체** | 9시간, 15분 | warning | 최장 주기 6h + 여유 |
| **R8 웹훅 재시도 정체** | 30분, 10분 | warning | 멈추면 결제 결과가 판매자에게 전달되지 않는다 |
| **R9 배치가 시작만 하고 미완료** | 격차 1시간, 30분 | warning | `outcome=threw` 는 NoData 라 실패를 못 잡는다 |

> R6~R9 는 `clamp_max(time() - gauge, 앱 가동시간)` 형태다. gauge 는 재기동 때 0 으로 리셋되는데,
> 상한을 씌우지 않으면 `time() - 0` 이 **56년**으로 계산돼 배포할 때마다 오발화한다.
> 실제로 그 상태의 규칙이 남아 발화한 적이 있다(아래 함정 표).

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
| **파일에서 규칙을 지워도 삭제되지 않음** | 옛 규칙이 DB 에 남아 계속 평가 — **496,448시간으로 오발화** | `deleteRules` 에 uid 명시. 검증기가 정합성 검사 |
| `job="groble-api"` 에 dev 가 섞임 | prod 전용 알람이 **dev 로도 울림**. `and on()` 은 쿼리 에러 | 검증기가 `environment` 필터 없는 식을 거부 |
| CORS preflight 를 성공으로 셈 | `OPTIONS` 200 이 2xx 의 24.8% — 결제 전멸해도 **안 울림** | 모든 HTTP 식에 `method!="OPTIONS"` |


---

## 검증

- [x] **API 태스크 워킹셋 측정·기록** (2-0) — 라이브 셋 최대 prod 510.5 MiB / dev 304.6 MiB
- [x] Prometheus `/targets`에서 **노드 3대 모두 UP** — 타깃 총 **14개**, 전환 전과 동일
- [x] Grafana 대시보드가 프로비저닝으로 복원 — Groble 폴더 3개, 읽기 전용 강제 확인
- [x] `up == 0` 알람과 **"기대 타깃 수 미달" 알람** 동작 확인 (health=ok)
- [x] **Slack 도달 검증** — critical·warning **두 채널 모두 도달 확인** (아래 「알림 경로 도달 검증」)
- [x] PR #7 머지 후 Grafana 재배포 → 알림 **8건** `state=active` · 평가 실패 0건 확인 (rev 47)
- [x] Grafana 재배포 후 알림 **14건** `state=active` · 평가 실패 0건 확인 (rev 49, `11.6.3-d1ac4d3`)
- [x] **prod** JVM 수정 배포 (2026-08-20, 힙 상한 900 MiB)
- [x] (Phase 7 진입 전) prod 재측정 → `memory_reservation` = **1,300 MiB** 확정 (2026-08-24)

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
