# [검수·요청] 결제 관측 — 알림 5건 검수 + 지표 3종 노출 요청

| | |
|---|---|
| **요청 대상** | groble-backend |
| **요청자** | 인프라 (groble-infra) |
| **작성일** | 2026-08-20 |
| **상태** | ⏳ **부분 회신 대기** — **A(알림 검수) ✅ 회신 완료**, R1~R9 로 반영·배포 완료. **B(지표 3종 노출) 대기 중** — 지표가 나오면 R10~R14 를 건다 ([Phase 2](../runbook/phase-02-observability.md)) |
| **기준선** | 운영 Prometheus, 직전 **14일** (문서 전체 동일 기준) |
| **관련** | [`backend-jvm-heap-limit.md`](./closed/backend-jvm-heap-limit.md) (별건) · [Phase 2 런북](../runbook/phase-02-observability.md) |

---

## 1. 무엇을 봐 주셔야 하나

두 가지입니다. **A 는 답만 주시면 되고, B 는 작업 요청입니다.**

**A. 이미 만든 알림 5건이 맞는지 검수** (§2~§4)

Grafana 에 결제 관련 알림 5건을 구성했습니다. 전부 **HTTP 상태코드와 스케줄러 gauge 만으로**
만든 것이라, **인프라 쪽에서는 "이 URI 가 정말 결제인가"를 판단할 수 없습니다.**
확인이 필요한 건 ① 감시 대상 목록(URI 7그룹 · job_id 11개)이 맞는가 ② 임계가 현실적인가 입니다.

**B. 앱이 지표 3종을 새로 내보내 주시기 요청** (§6)

A 를 아무리 손봐도 **구조적으로 못 보는 것**이 남습니다 — 정기결제 성공 여부, 승인 불명,
대사 불일치. 이건 앱이 지표를 내보내야만 풀립니다.

> ⚠️ 검수 중 **인프라 쪽 결함 1건을 이미 발견**했습니다 (§5). 그건 저희가 고칩니다.

---

## 2. 알림 규칙 5건 — 요약

| # | 알림 | 무엇이 일어나면 울리나 | 임계 | 지속 | 등급 | 도착 채널 |
|---|---|---|---|---|---|---|
| 1 | **결제 경로 서버 오류(5xx)** | 결제 URI 에서 5xx 가 15분간 1건 이상 | `> 0건 / 15분` | 즉시 | critical | `#groble-alert` |
| 2 | **결제 성공 부재** | 일반결제 2xx 가 2시간 동안 0건 | `< 1건 / 2시간` | 10분 | critical | `#groble-alert` |
| 3 | **결제 실패 급증** | 결제 URI 4xx+5xx 합계가 15분간 20건 초과 | `> 20건 / 15분` | 5분 | warning | `#groble-alert-dev` |
| 4 | **정기결제·정산 배치 정체 (일 1회)** | 일 1회 배치가 마지막 성공 후 25시간 경과 | `> 25시간` | 10분 | critical | `#groble-alert` |
| 5 | **주기 배치 정체 (6시간 이하)** | 단주기 배치가 마지막 성공 후 9시간 경과 | `> 9시간` | 10분 | warning | `#groble-alert-dev` |

각 알림에는 대응 절차(runbook)가 본문에 함께 실려 Slack 으로 갑니다.

---

## 3. 규칙별 상세 — 감시 대상과 근거

### 3-1. 결제 경로 서버 오류(5xx) · 결제 실패 급증 — 대상 URI 7개 그룹

두 알림이 **같은 URI 집합**을 봅니다. 1번은 5xx 만, 3번은 4xx+5xx 합계입니다.

```
/api/v1/content/{contentId}/pay
/api/v1/content/{contentId}/pay/{optionId}
/api/v1/content/{contentId}/checkout
/api/v1/checkouts/{checkoutId}
/api/v1/orders/create
/api/v1/payments/payple/**          (payple 연동 전부)
/api/v1/membership/subscribe**
```

**실측 (운영, 직전 14일)**

| 항목 | 값 |
|---|---|
| 결제 경로 총 요청 | 30,802건 |
| 4xx | **389건 (1.26%)** |
| **5xx** | **0건** |
| 15분 창당 실패 p50 / p90 / p99 / 최대 | **0 / 1 / 5 / 39건** |

→ 5xx 는 14일간 0건이므로 **1건이라도 나오면 이상**이라는 전제로 임계를 `> 0` 으로 잡았습니다.
→ 실패 급증 임계 20건은 p99(5건)와 최대(39건) 사이입니다.

**❓ 검수 질문**

| # | 질문 | 왜 묻나 |
|---|---|---|
| Q1 | `/api/v1/membership/subscribe/confirm`·`/subscribe/result` 는 **14일간 요청이 0건**입니다. 폐기된 경로인가요? 멤버십 구독 시작은 실제로 어느 엔드포인트를 타나요? | 죽은 경로를 감시하고 있으면 멤버십 결제 장애를 못 잡습니다 |
| Q2 | `/api/v1/content/{contentId}/pay` 의 **410 이 14일간 113건**입니다. 만료된 체크아웃으로 보이는데, **정상 동작이라면 "실패"에서 빼는 게 맞습니다.** | 정상 흐름이 실패 카운트를 밀어 올리면 임계가 무뎌집니다 |
| Q3 | **취소·환불 경로가 현재 전부 감시 밖**입니다. 넣어야 할까요? <br>`/api/v1/payment/{merchantUid}/cancel/request` (14일 7건) · `/api/v1/sell/orders/{merchantUid}/cancel*` (12건) · `/api/v1/sell/orders/subscriptions/{subscriptionId}/cancel` (12건) | 환불 실패는 결제 실패만큼 사용자 영향이 큽니다 |
| Q4 | `/api/v1/orders/{merchantUid}/release-reservation` (14일 427건, 그중 **400 이 14건**) 도 밖에 있습니다. **Redis 재고 예약 해제**로 보이는데, 실패하면 재고가 묶인 채 남나요? | Redis 는 재고 예약의 유일한 권위 소스라 무증상 누수가 됩니다 |
| Q5 | `/api/v1/guest/order/code-request`·`verify-request` (14일 119건) 는 비회원 주문 흐름의 일부인가요? | 비회원 결제 유입이 막히면 지금은 아무도 모릅니다 |

---

### 3-2. 결제 성공 부재 — **가장 확인이 필요한 규칙**

> *"실패가 늘지 않아도 성공이 0 이면 문제"* — 기존 알림들이 못 보던 각도입니다.
> 14일간 무증상으로 지나갈 뻔한 장애를 2시간 안에 잡는 것이 목적입니다.

**현재 세는 대상**

```
/api/v1/content/{contentId}/pay   의 2xx      (14일 GET 200 = 14,150건)
/api/v1/orders/create             의 2xx      (14일 POST 201 = 2,774건)
```

**실측 (2시간 창, 14일)**

| 항목 | 값 |
|---|---|
| 중앙값 | 124건 |
| **최소** | **8건** |
| 임계 | **0건일 때 발화** |

→ 최악의 2시간에도 8건이 있었으므로 오탐 여유가 8배입니다.

**❓ 검수 질문 — 이게 제일 중요합니다**

| # | 질문 | 왜 묻나 |
|---|---|---|
| **Q6** | **`GET /api/v1/content/{contentId}/pay` 가 실제 "결제 성공" 인가요?** GET 이라 결제 실행이 아니라 **결제 페이지 조회·결제 준비** 처럼 보입니다. 만약 그렇다면 이 알림은 *"결제가 되고 있는가"* 가 아니라 *"결제 페이지가 열리는가"* 를 재고 있는 것이고, **PG 승인이 전부 실패해도 조용합니다.** | 이 규칙의 존재 의의 자체가 걸려 있습니다 |
| Q7 | 그렇다면 **"결제가 실제로 완결됐다"를 가장 잘 나타내는 엔드포인트/상태코드는 무엇인가요?** `POST /api/v1/orders/create` 의 **201** 인가요, 아니면 payple 승인 콜백 쪽인가요? | 그 값으로 식을 바꾸겠습니다 |
| Q8 | `/api/v1/content/{contentId}/pay/{optionId}` (14일 GET 200 = 1,511건) 는 현재 **성공 집계에서 빠져** 있습니다. 옵션 결제도 결제 완결로 봐야 하나요? | 단품/옵션 중 한쪽만 죽는 장애를 놓칩니다 |
| Q9 | **정기결제(빌링) 성공은 지금 완전히 감시 밖**입니다. 배치 안에서 일어나 HTTP 지표가 없기 때문입니다. 현재는 4번(배치 정체) 알림이 *"배치가 아예 안 돌았다"* 까지만 잡고, **배치는 돌았는데 전건 승인 실패한 경우는 못 잡습니다.** 이건 **§6 의 `groble.payment.attempts`** 로만 해결됩니다. | 정기결제가 조용히 전멸하는 시나리오가 열려 있습니다 |

---

### 3-3. 배치 정체 2건 — 감시 중인 스케줄러 11개

`groble_scheduled_last_completed_timestamp_seconds` gauge 를 씁니다.
**마지막 성공 완료로부터 경과 시간**이 임계를 넘으면 발화하며, Slack 에 `job_id` 가 그대로 찍힙니다.

**① 일 1회 배치 — 임계 25시간 (critical)**

| 실행 시각(14일 실측) | job_id |
|---|---|
| 06:00 | `PaymentReconciliationScheduler.runDailyReconciliation` |
| 08:00 | `SettlementReconciliationScheduler.runDailyReconciliation` |
| 08:30 | `MembershipBillingScheduler.runBillingFailedCancelNotification` |
| 09:00 | `SubscriptionBillingScheduler.runSubscriptionBilling` |
| 09:05 | `SubscriptionBillingScheduler.runCancelNotification` |
| 09:30 | `MembershipBillingScheduler.runMembershipBilling` |
| 10:00 | `MembershipBillingScheduler.runTrialEndNotification` |

→ 임계 25시간 = 주기 24시간 + 여유 1시간. **예정 시각 1시간 뒤**에 감지됩니다.

**② 단주기 배치 — 임계 9시간 (warning)**

| 주기 | job_id |
|---|---|
| 12분 | `MembershipBillingScheduler.runExpiredTrialsAndGrants` |
| 1시간 | `MembershipBillingScheduler.runExpiredCancelled` |
| 1시간 | `MembershipBillingScheduler.runExpiredGracePeriods` |
| 6시간 | `SubscriptionBillingScheduler.runGracePeriodExpiration` |

→ 임계 9시간 = 최장 주기 6시간 + 여유.

**❓ 검수 질문**

| # | 질문 | 왜 묻나 |
|---|---|---|
| Q10 | 위 **주기 분류(일 1회 / 6시간 이하)가 맞나요?** 14일 실측에서 역산한 값이라, 코드상 cron 과 다를 수 있습니다 | 주기를 잘못 알면 임계가 통째로 틀립니다 |
| Q11 | gauge 에는 스케줄러가 **총 23개** 있는데 11개만 감시 중입니다. 아래 중 **결제·정산에 영향이 있어 감시해야 할 것**이 있나요? <br>`WebhookRetryScheduler.retryFailedDeliveries` · `WebhookRetryScheduler.recoverStuckInFlightDeliveries` · `SettlementNotificationScheduler.runDailyNotice` · `SettlementNotificationScheduler.runEveningReminder` · `ContentSaleEndScheduler.processExpiredContents` | 웹훅 재시도가 멈추면 결제 결과 전달이 밀릴 수 있어 보입니다 |
| Q12 | `MembershipBillingScheduler.runMembershipBilling` 은 **08-11 ~ 08-18 구간에 gauge 가 0 인 샘플이 30%(134/453)** 였습니다. 그 기간 **한 번도 완료되지 않았다**는 뜻인데, 보고하신 장애와 같은 건인가요? | 같은 건이면 이 알림이 그때 잡았을 것이라는 근거가 됩니다 |

---

## 4. 지금 감시 밖에 있는 결제성 URI 전체 (판단용)

요청량 상위만 추렸습니다. **넣을지 말지 판단만 해 주시면 됩니다.**

| 14일 요청 | URI | 인프라 추정 |
|---|---|---|
| 4,421 | `/api/v1/orders/success/{merchantUid}` | 결제 완료 페이지 조회? |
| 1,946 | `/api/v1/purchase/content/my/{merchantUid}` | 구매 내역 조회 |
| 427 | `/api/v1/orders/{merchantUid}/release-reservation` | **재고 예약 해제 (Q4)** |
| 693 | `/api/v1/users/me/payment-methods` | 결제수단 조회 |
| 119 | `/api/v1/guest/order/*` | **비회원 주문 (Q5)** |
| 99 | `/api/v1/checkouts/{checkoutId}/coupon` | 체크아웃 쿠폰 적용 |
| 31 | 취소·환불 경로 일체 | **(Q3)** |

> `/api/v1/admin/**` 은 전부 제외했습니다 — 운영자 화면이라 사용자 결제 흐름이 아닙니다.
> 다만 `admin/payments/approval-unknowns` 가 존재한다는 건 **앱이 이미 "승인 불명"을 알고 있다**는 뜻이고,
> 그 값이 지표로 나오면 훨씬 정확한 알림이 됩니다 → **§6**.

---

## 5. 인프라가 검수 중 발견한 결함 (저희가 고칩니다 — 참고용)

**`결제 성공 부재` 알림이 CORS preflight 를 성공으로 세고 있었습니다.**

`OPTIONS` 요청은 Spring 필터 체인이 컨트롤러에 닿기 전에 200 을 돌려주므로,
**앱이 떠 있기만 하면 결제가 전멸해도 계속 200 이 쌓입니다.**

| | 14일 |
|---|---|
| 대상 URI 의 2xx 총계 | 22,491건 |
| 그중 **`OPTIONS` 200** | **5,567건 (24.8%)** |

임계가 "0건일 때 발화"라서, **preflight 가 하루 400건씩 들어오는 한 이 알림은 영영 울리지 않습니다.**
식에 `method!="OPTIONS"` 를 추가해 고치겠습니다 (수정 후 2시간 창 최소 8 → 7건, 오탐 여유는 그대로).

---

## 6. [작업 요청] 결제 결과를 지표로 노출해 주세요

> 여기부터는 검수가 아니라 **작업 요청**입니다. 긴급도 중간 — 장애 대응 속도에 직결되나
> 서비스 중단을 유발하진 않습니다.

### 6-1. 왜 필요한가 — 개별 결제 실패가 아무에게도 알려지지 않습니다

§2 의 알림 5건은 전부 HTTP 상태코드 기반이라 **"실패가 늘었다"까지만** 말합니다.
사유도, 건별 식별도 불가능합니다.

**14일 실측 — 결제 경로 실패 389건 내역**

| 건수 | 상태 | 엔드포인트 |
|---|---|---|
| 120 | 400 | `/api/v1/content/{contentId}/pay` |
| **113** | **410** | `/api/v1/content/{contentId}/pay` |
| 107 | 400 | `/api/v1/orders/create` |
| 31 | 400 | `/api/v1/checkouts/{checkoutId}` |
| 6 | 401 | `/api/v1/orders/create` |
| 6 | 400 | `/api/v1/payments/payple/app-card/request` |
| 4 | 400 | `/api/v1/payments/payple/subscription/{merchantUid}/resume` |
| 2 | 404 | `/api/v1/content/{contentId}/pay` |

> 하루 평균 **27.8건**의 결제 시도가 실패로 끝나고 있는데, 이 중 무엇이 정상적인 사용자 오류이고
> 무엇이 시스템 문제인지 **인프라 쪽에서는 구분할 방법이 없습니다.**
> 특히 **410(Gone) 113건**이 그렇습니다 — 만료된 체크아웃이라면 정상이지만,
> 재고 예약이 잘못 풀린 것이라면 문제입니다 (§3-1 Q2 와 같은 건).

### 6-2. 앱은 이미 알고 있는데 노출만 안 하고 있습니다

admin API 에 이런 엔드포인트가 있습니다.

```
/api/v1/admin/payments/approval-unknowns               ← PG 승인 결과 불명
/api/v1/admin/payment-reconciliations/discrepancies    ← 결제 대사 불일치
/api/v1/admin/settlement-reconciliations/discrepancies ← 정산 대사 불일치
```

**결제 시스템에서 가장 위험한 상태들입니다** — 돈은 빠져나갔는데 주문이 안 잡혔거나, 장부가 안 맞는 경우.
`/approval-unknowns/{merchantUid}/confirm` 이 **14일간 실제로 4번 호출**된 흔적이 있어,
누군가 수동으로 처리한 적이 있습니다. 그때 알림은 한 건도 가지 않았습니다.

`PaymentReconciliationScheduler.runDailyReconciliation` 이 매일 대사를 돌고 있으므로
**계산은 이미 하고 있고 노출만 안 하는 상태**입니다.

### 6-3. 요청 사항

**① (최우선) 대사 불일치 — Gauge**

```java
// 대사 배치가 끝날 때마다 현재 불일치 건수를 갱신
Gauge.builder("groble.reconciliation.discrepancies", this, s -> s.currentDiscrepancyCount())
     .tag("type", "payment")        // payment | settlement
     .register(meterRegistry);
```

**결제 서비스에서 가장 중요한 단일 지표입니다.** 0 을 벗어나면 장부가 안 맞는다는 뜻이고,
인프라가 즉시 Slack 알람을 걸 수 있습니다. 계산은 이미 하고 계시니 노출만 해주시면 됩니다.

**② (최우선) 승인 불명 — Gauge**

```java
// 미해결 승인 불명 건수
Gauge.builder("groble.payment.approval_unknown", ...)
```

0 을 넘으면 사람이 개입해야 하는 상태입니다.

**③ 결제 시도 결과 — Counter**

```java
Counter.builder("groble.payment.attempts")
       .tag("outcome", "success|failed|unknown")
       .tag("reason", "<실패 사유 코드>")   // ⚠️ 카디널리티 주의 (6-5)
       .tag("pg", "payple")
       .tag("type", "onetime|subscription")
       .register(meterRegistry).increment();
```

이게 있으면 **"PG 장애로 실패"와 "사용자 카드 한도 초과"를 구분**할 수 있습니다. 지금은 둘 다 그냥 400 입니다.
**그리고 `type="subscription"` 이 있으면 §3-2 Q9 의 공백 — 정기결제 성공 감시 — 이 그대로 해결됩니다.**

### 6-4. 배치 실패가 계측되는지 확인 부탁드립니다

`groble_scheduled_runs_total` 의 `outcome` 라벨에 **`returned` 값만 존재**합니다 (14일 기준 20개 시계열 전부).
배치가 실패한 적이 없어서인지, 실패가 계측되지 않는 것인지 인프라 쪽에서는 구분할 수 없습니다.

**즉 §2 의 배치 정체 알림 2건이 실제로 동작하는지 검증되지 않은 상태입니다.**
예외 발생 시에도 카운터가 `outcome != returned` 로 증가하는지 확인해 주세요.

### 6-5. ⚠️ 카디널리티 제약 — 반드시 지켜주세요

**`reason` 태그에 자유 문자열을 넣지 마세요.** 정해진 코드 집합(수십 개 이내)만 사용해 주십시오.
`merchantUid`, `userId`, 주문번호 같은 **고유값을 라벨로 넣으면 안 됩니다.**

이유: 현재 Prometheus 는 활성 시계열 약 40,000개에 **컨테이너 하드리밋이 512 MiB** 입니다.
이미 `http_server_requests_seconds_bucket` 하나가 전체의 43%(17,457개)를 차지하고 있고,
실제로 무거운 쿼리 한 번에 **OOM 으로 죽은 적이 있습니다.**
고유값 라벨은 시계열을 무제한으로 늘려 관측 시스템 자체를 무너뜨립니다.

건별 추적이 필요하면 지표가 아니라 **로그(Loki)** 를 쓰는 것이 맞습니다.

### 6-6. 이 지표가 생기면 인프라가 거는 알람

| 알람 | 조건 | severity | Slack |
|---|---|---|---|
| 결제 대사 불일치 발생 | `groble_reconciliation_discrepancies > 0` | critical | `#groble-alert` |
| 승인 불명 미해결 | `groble_payment_approval_unknown > 0` (30분 지속) | critical | `#groble-alert` |
| 정기결제 성공 부재 | `type="subscription"` 성공이 24시간 0건 | critical | `#groble-alert` |
| PG 연동 장애 | `reason` 이 PG 계열인 실패의 급증 | critical | `#groble-alert` |
| 결제 실패율 상승 | 사유별 실패 비율이 기준선 대비 상승 | warning | `#groble-alert-dev` |

**현재는 이 중 무엇도 걸 수 없습니다.**

---

## 7. 회신 방법

**A(검수)** 는 Q1~Q12 중 답할 수 있는 것만 주시면 됩니다.
그중 **Q6 — GET `/api/v1/content/{contentId}/pay` 가 실제 결제 성공인가** 하나만 먼저 받아도
나머지는 저희가 조정할 수 있습니다.

**B(지표)** 는 이름·라벨만 확정해서 알려주시면 알람과 대시보드 패널은 인프라에서 붙이겠습니다.
셋 다 한 번에 안 되면 **6-3 ①(대사 불일치)** 하나만 먼저도 좋습니다.

반영 후 `groble-images` PR 을 머지하고 Grafana 를 재배포합니다.

### 참고

| | |
|---|---|
| 알림 경로 | Grafana → SNS → AWS Chatbot → Slack (Phase 1 구축) |
| 알림 규칙 정의 | `groble-images` 의 `grafana/provisioning/alerting/rules.yaml` |
| 대시보드 | `Groble — 백엔드` (Grafana), 결제·정산 배치 패널은 `Groble — 개요` |
| 기준선 수집 | [Phase 2 런북](../runbook/phase-02-observability.md) |
