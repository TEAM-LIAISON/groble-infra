# [요청] HTTP 지표가 500 을 10건 중 4건만 기록한다 + 스케줄러 10개 감시 공백

| | |
|---|---|
| **요청 대상** | groble-backend |
| **요청자** | 인프라 (groble-infra) |
| **작성일** | 2026-08-30 |
| **상태** | ⏳ **회신 대기** |
| **기준선** | 운영 Prometheus / ALB CloudWatch / Loki, 2026-08-28 17:00~17:40 UTC (= 08-29 02:00~02:40 KST) |
| **관련** | [`payment-alerts-review.md`](./payment-alerts-review.md) (알림 규칙 원본) · [Phase 2 런북](../runbook/phase-02-observability.md) · [Phase 1 런북](../runbook/phase-01-alarm-backstop.md) |

---

## 1. 무엇을 봐 주셔야 하나

**두 건입니다. A 는 원인 조사 요청이고, B 는 정보 요청입니다.**

**A. 앱이 반환한 500 열 건 중 네 건만 `http_server_requests` 에 기록됐습니다** (§2~§4)

같은 사건을 세 곳에서 셌는데 앱 지표만 숫자가 다릅니다. **인프라에서는 원인을 특정하지
못했습니다** — 스레드 고갈도, 커넥션 풀 고갈도, 태스크 재기동도 아니었습니다.

**B. 스케줄러 23개 중 10개가 어떤 정체 알람에도 걸려 있지 않습니다** (§5)

알람은 저희가 답니다. 다만 **각 배치의 실행 주기와 중요도를 저희가 알 수 없어**
임계를 정할 수 없습니다.

> 이 사건에서 발견된 **인프라 쪽 결함 1건은 이미 고쳐 배포했습니다** (§4 마지막).
> 이 문서에서 답을 기다리는 것은 위 A·B 뿐입니다.

---

## 2. 무슨 일이 있었나

2026-08-29 02:21~02:23 KST, **RDS MySQL 8.4 Blue/Green 스위치오버** 중 구 인스턴스가
read-only 로 전환됐는데 앱이 계속 그쪽에 쓰고 있었습니다. 5분간 500 이 발생했습니다.

Loki 로그 10건이 전부 동일한 예외입니다:

```
org.springframework.orm.jpa.JpaSystemException: could not execute statement
  [The MySQL server is running with the --read-only option so it cannot execute this statement]
```

> 이 사건 자체는 이미 원인이 파악돼 있습니다 (JVM 의 DNS 캐시). 02:23 의 배포로 해소됐고,
> **이 문서가 묻는 것은 사건이 아니라 "왜 지표에 4건만 남았는가" 입니다.**

---

## 3. 세 출처를 대조한 결과

| 출처 | 17:21 | 17:23 | 합계 |
|---|---|---|---|
| ALB `HTTPCode_Target_5XX_Count` (CloudWatch) | 8 | 2 | **10** |
| Loki `GlobalExceptionHandler` ERROR 로그 | 8 | 2 | **10** |
| **Prometheus `http_server_requests_seconds_count{status="5.."}`** | — | — | **4** |

**ALB 와 로그는 분 단위까지 정확히 일치합니다.** 앱 지표만 6건이 비어 있습니다.

Prometheus 에 남은 시계열은 이 둘이 전부입니다 (원시 카운터 값, `increase()` 아님):

```
POST /api/v1/orders/create              status=500 outcome=SERVER_ERROR exception=none
    첫 샘플 17:22:00Z = 2   마지막 17:26:00Z = 2

POST /api/v1/content/track/{contentId}  status=500 outcome=SERVER_ERROR exception=none
    첫 샘플 17:23:30Z = 1   마지막 17:26:00Z = 2
```

합계 4건입니다. 나머지 6건에 해당하는 시계열은 **존재하지 않습니다.**

---

## 4. 인프라가 배제한 것

추측을 줄이시라고, 저희가 확인해서 **아닌 것으로 판명된 가설**을 적어 둡니다.

| 가설 | 확인 결과 |
|---|---|
| 스레드 고갈로 Tomcat 이 요청을 거절 | ❌ live threads 56~62 로 안정. 10건 모두 `http-nio-8080-exec-*` 스레드에서 처리됨 |
| DB 커넥션 풀 대기 | ❌ HikariCP `pending` 0, `active` 0~1 |
| 태스크 재기동으로 카운터 유실 | ❌ 재기동은 17:24 경. 문제의 500 은 17:21~17:23 이고, 구 태스크는 17:26 까지 살아서 스크레이프됐다 |
| `uri` 라벨이 `/error` 나 `UNKNOWN` 으로 빠짐 | ❌ 해당 시계열 없음 |
| Micrometer 필터 앞단(서블릿 필터)에서 예외 | ❌ 10건 모두 `GlobalExceptionHandler` 를 거쳤다 (로그로 확인) |
| 스크레이프 실패 | ❌ `up{job="groble-api"}` 가 구간 내내 1 |

**즉 "정상적으로 컨트롤러까지 도달해 `GlobalExceptionHandler` 가 500 을 반환했는데,
그중 6건이 `http_server_requests` 에 계상되지 않았다"** 가 남은 사실입니다.

> **인프라 쪽 결함(고침 완료)**: 저 4건 중 `POST /api/v1/orders/create` 2건은 결제 경로
> 알람의 감시 대상인데도 알람이 울리지 않았습니다. `increase()` 가 **시계열이 없다가
> 생기는 순간을 못 보는** 문제였고, 2026-08-30 에 수정·배포했습니다
> ([groble-images#12](https://github.com/TEAM-LIAISON/groble-images/pull/12)).
> **이건 저희 문제였고 이미 해결됐습니다.**

### 질문 (A)

**A-1.** `GlobalExceptionHandler` 가 처리한 응답이 `http_server_requests` 에 계상되지 않는
경로가 있습니까? (예: `@ExceptionHandler` 가 `ResponseEntity` 대신 다른 방식으로 응답하는 경우,
`WebMvcMetricsFilter` 보다 바깥에서 응답이 커밋되는 경우)

**A-2.** 결제/주문 계열에 **비동기 처리나 `@Async` 경계**가 있어 HTTP 응답과 예외 발생 스레드가
갈라지는 구간이 있습니까? (같은 시각 `app-async-1` 스레드에서도 동일 예외가 났습니다)

**A-3.** Micrometer 나 액추에이터 관련 설정 중 **URI 태그 상한**(`management.metrics.web.server.max-uri-tags`)
이나 필터를 커스터마이즈한 것이 있습니까? 상한에 걸리면 새 시계열이 조용히 버려집니다.

**A-4.** 위로 설명되지 않는다면, **재현 가능한 최소 케이스**를 만들어 주실 수 있습니까?
`GlobalExceptionHandler` 를 타는 500 을 N번 발생시키고
`/actuator/prometheus` 에서 `http_server_requests_seconds_count{status="500"}` 이
N만큼 오르는지만 확인하면 됩니다.

### 왜 중요한가

**Grafana 의 결제 알람 R1·R3·R4 는 전부 이 지표 하나에 의존합니다.**
지표가 실제의 40% 만 기록한다면, 임계를 아무리 낮춰도 그만큼 둔감합니다.
이번에는 ALB 알람(CloudWatch)이 받아냈지만, **ALB 는 URI 별로 구분하지 못해
"결제 경로가 죽었는지"를 판단할 수 없습니다.** 그건 앱 지표만 할 수 있는 일입니다.

---

## 5. 스케줄러 10개가 감시 공백에 있다 (B)

`groble_scheduled_last_completed_timestamp_seconds` 로 배치 정체를 감시하는 알람 3건
(일 1회 / 단주기 / 웹훅)이 있습니다. **[`payment-alerts-review.md`](./payment-alerts-review.md)
회신 때 지정해 주신 13개**만 `job_id` 목록에 들어 있는데, 운영에는 **23개**가 노출되고 있습니다.

아래 10개는 **멈춰도 Slack 이 울리지 않습니다.**

| job_id | 감시 |
|---|---|
| `SettlementNotificationScheduler.runDailyNotice` | ❌ |
| `SettlementNotificationScheduler.runEveningReminder` | ❌ |
| `ContentSaleEndScheduler.processExpiredContents` | ❌ |
| `ViewStatsScheduler.aggregateDailyStats` | ❌ |
| `ViewStatsScheduler.aggregateMonthlyStats` | ❌ |
| `MakerReminderEmailScheduler.sendWeekdayReminder` | ❌ |
| `MakerReminderEmailScheduler.sendWeekendReminder` | ❌ |
| `MakerVerificationReminderEmailScheduler.sendWeekdayReminder` | ❌ |
| `MakerVerificationReminderEmailScheduler.sendWeekendReminder` | ❌ |
| `ReferrerTrackingCleanupScheduler.purgeExpiredReferrerTracking` | ❌ |

> `groble-batch-repeatedly-failing` 알람은 `job_id` 필터가 없어 23개 전부를 보지만,
> **"시작해 놓고 끝나지 않는" 경우만** 잡습니다. 스케줄러가 아예 돌지 않으면
> `last_started` 도 같이 멈춰 격차가 0이라 이 알람도 침묵합니다.

### 질문 (B)

**B-1.** 위 10개 중 **멈추면 사용자·정산에 영향이 있는 것**은 무엇입니까?
(저희 눈에는 `SettlementNotificationScheduler` 와 `ContentSaleEndScheduler` 가
그래 보이지만 판단은 백엔드 몫입니다)

**B-2.** 각각의 **실행 주기**를 알려주십시오. 임계는 `주기 + 여유` 로 잡습니다
(현재 일 1회 계열은 25시간, 단주기 계열은 9시간).

**B-3.** 감시할 필요가 **없는 것**은 없다고 말씀해 주십시오. 그대로 두겠습니다 —
울릴 필요 없는 알람을 다는 것이 안 다는 것보다 나쁩니다.

**B-4.** 앞으로 스케줄러를 추가하실 때 알려주실 방법이 있을까요?
지금 구조는 `job_id` 를 하나하나 열거하는 방식이라, 새 스케줄러가 생기면
**아무도 모르게 감시 공백이 늘어납니다.**

---

## 6. 확인용 쿼리

직접 보실 수 있도록 남깁니다. 운영 Prometheus 는 `10.0.1.193:9090` (WireGuard VPN 경유)입니다.

**A — 사건 구간의 5xx 원시 카운터**

```promql
http_server_requests_seconds_count{environment="production",job="groble-api",status=~"5.."}
```

시간 범위를 `2026-08-28 17:00 ~ 17:40 UTC` 로 두고 보십시오.
`increase()` 를 씌우면 안 됩니다 — 위 §4 에 적은 이유로 값이 0으로 보입니다.

**B — 현재 노출 중인 스케줄러 전체 목록**

```promql
count by (job_id) (groble_scheduled_last_completed_timestamp_seconds{environment="production"})
```

**B — 마지막 완료 후 경과 시간(시간 단위)**

```promql
clamp_max(
  time() - groble_scheduled_last_completed_timestamp_seconds{environment="production",job="groble-api"},
  scalar(max(process_uptime_seconds{environment="production",job="groble-api"}))
) / 3600
```

---

## 7. 요약

| | 요청 | 막혀 있는 것 |
|---|---|---|
| **A** | 500 이 `http_server_requests` 에 40% 만 계상되는 원인 조사 | 결제 알람 R1·R3·R4 의 신뢰도 |
| **B** | 스케줄러 10개의 중요도·실행 주기 | 배치 정체 알람의 감시 범위 |

**둘 다 진행 중인 Phase 를 막지는 않습니다.** 다만 A 는 이미 만들어 둔 알림의
정확도에 직접 걸리는 문제라, 시간이 되실 때 우선 봐 주시면 좋겠습니다.
