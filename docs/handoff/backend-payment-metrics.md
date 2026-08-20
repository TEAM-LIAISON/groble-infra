# [작업 요청] groble-backend — 결제 결과를 지표로 노출

| | |
|---|---|
| **요청 대상** | groble-backend (Micrometer 지표 추가) |
| **요청자** | 인프라 (groble-infra) |
| **작성일** | 2026-08-20 |
| **긴급도** | 중간 — 장애 대응 속도에 직결되나 서비스 중단을 유발하진 않는다 |
| **관련** | [`backend-jvm-heap-limit.md`](./backend-jvm-heap-limit.md) (별건) |

---

## 1. 한 줄 요약

**개별 결제 실패가 아무에게도 알려지지 않습니다.** 특히 앱이 이미 계산하고 있는
**승인 불명(approval-unknown)과 대사 불일치(reconciliation discrepancy)** 가 지표로 노출되지 않아,
사람이 admin 화면을 열어보기 전까지 알 수 없습니다. 이 세 가지를 Micrometer 지표로 내보내 주시기를 요청드립니다.

---

## 2. 현재 상태 — 무엇이 감지되고 무엇이 안 되나

### 2.1 지금 있는 알림

| 알림 | 무엇을 잡나 | 결제 실패를 잡나 |
|---|---|---|
| 결제·정산 배치 정체 (Grafana) | 빌링/대사 배치가 26시간 넘게 성공 못함 | ✗ **배치가 통째로 멈춘 경우만** |
| ALB 5xx / 지연 (CloudWatch, Phase 1) | ALB 레벨 오류율 | ✗ 결제 실패는 대부분 4xx이고, 5xx여도 전체에 묻힘 |
| 결제 경로 5xx / 실패 급증 (Grafana, 신규) | HTTP 상태코드 기반 | △ **"실패가 늘었다"까지만.** 사유·건별 식별 불가 |

### 2.2 실측 (운영 Prometheus, 직전 7일)

| 항목 | 값 |
|---|---|
| 결제 경로 요청 | 16,875건 |
| 실패(4xx/5xx) | **263건 (1.56%)** |
| 5xx | **0건** |

실패 내역:

| 건수 | 상태 | 엔드포인트 |
|---|---|---|
| 112 | 400 | `/api/v1/content/{contentId}/pay` |
| **70** | **410** | `/api/v1/content/{contentId}/pay` |
| 56 | 400 | `/api/v1/orders/create` |
| 17 | 400 | `/api/v1/checkouts/{checkoutId}` |
| 5 | 401 | `/api/v1/orders/create` |
| 3 | 400 | `/api/v1/payments/payple/app-card/request` |

> 하루 평균 **37.6건**의 결제 시도가 실패로 끝나고 있고, 이 중 무엇이 정상적인 사용자 오류이고
> 무엇이 시스템 문제인지 **인프라 쪽에서는 구분할 방법이 없습니다.**
> 특히 **410(Gone) 70건**이 무엇인지 알 수 없습니다 — 만료된 체크아웃이라면 정상이지만,
> 재고 예약이 잘못 풀린 것이라면 문제입니다.

### 2.3 앱은 이미 알고 있는데 노출하지 않습니다

admin API에 이런 엔드포인트가 있습니다.

```
/api/v1/admin/payments/approval-unknowns              ← PG 승인 결과 불명
/api/v1/admin/payment-reconciliations/discrepancies   ← 결제 대사 불일치
/api/v1/admin/settlement-reconciliations/discrepancies ← 정산 대사 불일치
```

**결제 시스템에서 가장 위험한 상태들입니다** — 돈은 빠져나갔는데 주문이 안 잡혔거나, 장부가 안 맞는 경우.
`/approval-unknowns/{merchantUid}/confirm`이 **실제로 6번 호출된 흔적**이 있어, 누군가 수동으로 처리한 적이 있습니다.

`PaymentReconciliationScheduler.runDailyReconciliation`이 매일 대사를 돌고 있으므로
**계산은 이미 하고 있고 노출만 안 하는 상태**입니다.

### 2.4 배치 실패가 계측되는지도 불확실합니다

`groble_scheduled_runs_total`의 `outcome` 라벨에 **`returned` 값만 존재**합니다.
배치가 실패한 적이 없어서인지, 실패가 계측되지 않는 것인지 인프라 쪽에서는 구분할 수 없습니다.
**즉 "배치 정체" 알람이 실제로 동작하는지 검증되지 않은 상태입니다.**

---

## 3. 요청 사항

### 3.1 (최우선) 대사 불일치 — Gauge

```java
// 대사 배치가 끝날 때마다 현재 불일치 건수를 갱신
Gauge.builder("groble.reconciliation.discrepancies", this, s -> s.currentDiscrepancyCount())
     .tag("type", "payment")        // payment | settlement
     .register(meterRegistry);
```

**결제 서비스에서 가장 중요한 단일 지표입니다.** 이 값이 0을 벗어나면 장부가 안 맞는다는 뜻이고,
인프라가 즉시 Slack 알람을 걸 수 있습니다. 계산은 이미 하고 계시니 노출만 해주시면 됩니다.

### 3.2 (최우선) 승인 불명 — Counter 또는 Gauge

```java
// 미해결 승인 불명 건수
Gauge.builder("groble.payment.approval_unknown", ...)
```

미해결 건수가 0을 넘으면 사람이 개입해야 하는 상태입니다.

### 3.3 결제 시도 결과 — Counter

```java
Counter.builder("groble.payment.attempts")
       .tag("outcome", "success|failed|unknown")
       .tag("reason", "<실패 사유 코드>")   // ⚠️ 카디널리티 주의 (3.5 참조)
       .tag("pg", "payple")
       .tag("type", "onetime|subscription")
       .register(meterRegistry).increment();
```

이게 있으면 **"PG 장애로 실패"와 "사용자 카드 한도 초과"를 구분**할 수 있습니다.
지금은 둘 다 그냥 400입니다.

### 3.4 배치 실패 계측 확인

`groble_scheduled_runs_total`에 실패 시 `outcome`이 `returned` 이외의 값으로 기록되는지
확인 부탁드립니다. 안 된다면 예외 발생 시에도 카운터가 증가하도록 해주세요 —
그렇지 않으면 "배치가 실패했지만 실행은 됐다"를 감지할 수 없습니다.

### 3.5 ⚠️ 카디널리티 제약 — 반드시 지켜주세요

**`reason` 태그에 자유 문자열을 넣지 마세요.** 정해진 코드 집합(수십 개 이내)만 사용해 주십시오.
`merchantUid`, `userId`, 주문번호 같은 **고유값을 라벨로 넣으면 안 됩니다.**

이유: 현재 Prometheus는 활성 시계열 약 40,000개에 **컨테이너 하드리밋이 512 MiB**입니다.
이미 `http_server_requests_seconds_bucket` 하나가 전체의 43%(17,457개)를 차지하고 있고,
실제로 무거운 쿼리 한 번에 **OOM으로 죽은 적이 있습니다.**
고유값 라벨은 시계열을 무제한으로 늘려 관측 시스템 자체를 무너뜨립니다.

건별 추적이 필요하면 지표가 아니라 **로그(Loki)** 를 쓰는 것이 맞습니다.

---

## 4. 이 지표가 생기면 인프라가 거는 알람

| 알람 | 조건 | severity | Slack |
|---|---|---|---|
| 결제 대사 불일치 발생 | `groble_reconciliation_discrepancies > 0` | critical | `#groble-alert` |
| 승인 불명 미해결 | `groble_payment_approval_unknown > 0` (30분 지속) | critical | `#groble-alert` |
| 결제 실패율 상승 | 사유별 실패 비율이 기준선 대비 상승 | warning | `#groble-alert-dev` |
| PG 연동 장애 | `reason` 이 PG 계열인 실패의 급증 | critical | `#groble-alert` |

현재는 이 중 무엇도 걸 수 없습니다.

---

## 5. 참고

| | |
|---|---|
| 알림 경로 | Grafana → SNS → AWS Chatbot → Slack (Phase 1 구축) |
| 알림 규칙 정의 | `groble-images` 의 `grafana/provisioning/alerting/rules.yaml` |
| 대시보드 | `Groble — 백엔드` (Grafana), 결제·정산 배치 패널은 `Groble — 개요` |
| 기준선 수집 | `groble-infra/docs/runbook/phase-02-observability.md` |

지표를 추가하시면 알려주세요. 이름·라벨만 확정되면 알람과 대시보드 패널은 인프라에서 붙이겠습니다.
