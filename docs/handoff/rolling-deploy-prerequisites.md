# [요청] 롤링 배포 전환의 앱 측 준비 4건

| | |
|---|---|
| **요청 대상** | groble-backend |
| **요청자** | 인프라 (groble-infra) |
| **작성일** | 2026-08-30 |
| **상태** | 🔄 **진행 중** — [§4 회신](#4-회신-groble-backend-2026-09-01)(09-01) · [§5 인프라 회답](#5-인프라-회답-groble-infra-2026-09-02)(09-02). **착수 조건이 4건 → 5건이 됐다**(스케줄러 추가). 대기: 앱 SIGTERM 실측 · 스케줄러 전수 점검 |
| **관련** | [Phase 6 런북 — 배포 컨트롤러 전환](../runbook/phase-06-deployment-controller.md) · [계획서 §2.6 · §3](../plan/infra-ha-improvement-plan.md) |

---

## 1. 무엇을 봐 주셔야 하나

**롤링 배포로 전환하기 위한 앱 측 준비 4건입니다.** 정해진 기한은 없으나
**전부 끝나기 전에는 전환에 착수하지 않습니다.**

> ⚠️ **2026-09-01 회신에서 5번째 조건이 추가됐습니다** — 스케줄러 23개의 다중 실행 안전성
> ([§4-5 A](#4-5-요청서에-없던-항목--저희가-먼저-알려드립니다)). 백엔드가 먼저 발견해 신고한 건입니다.

> JVM DNS 캐시 건은 [`closed/jvm-dns-cache.md`](./closed/jvm-dns-cache.md) 로 분리했고 종결됐습니다.

> **회신이 도착했습니다 → [§4](#4-회신-groble-backend-2026-09-01).** 3번(graceful shutdown)은 이미 적용돼
> 있었고, 2번은 **인프라 쪽 3건(ALB 경로·ECS 경로·WAF)이 세트로 필요**합니다. 4번 예시 값에는
> 이견이 있습니다(**dereg 60 / stopTimeout 90** 제안). 요청서에 없던 **스케줄러 다중 실행** 1건이
> 추가로 올라왔습니다.
>
> **인프라 회답도 붙였습니다 → [§5](#5-인프라-회답-groble-infra-2026-09-02).** I-1~I-4 모두 동의하되
> **I-1 은 지목 위치가 다르고 선행 리팩터가 필요**하며, `stopTimeout` 은 노드가 아니라 **태스크 정의**로
> 넣습니다. "앱 PR 과 동시에 나가야 한다"는 **불필요합니다 — 앱이 먼저가 안전합니다.**
> 착수 조건은 **4건 → 5건**이 됐습니다. 순서는 [§5-7](#5-7-정리--누가-언제-무엇을).

---

## 2. 롤링 배포 전환 준비 4건

### 배경: 왜 배포 방식을 바꾸나

인프라를 EC2 2대 구성으로 옮기면서 API 태스크를 2개로 늘립니다. 그런데
**블루/그린은 배포할 때 구·신 태스크가 모두 떠 있어야 해서 4자리가 필요**한데,
2대가 담을 수 있는 자리도 정확히 4개입니다. **노드가 1대라도 빠지면 배포가 아예 안 됩니다.**
롤링은 3자리면 되어 1자리가 남습니다.

### 그래서 무엇이 달라지나 — **이게 요청의 이유입니다**

지금 블루/그린은 트래픽을 **한 번에** 넘깁니다. 구버전과 신버전이 **동시에 실사용자
요청을 받는 순간이 없습니다.**

롤링은 태스크를 하나씩 교체하므로, 배포 중 **구버전과 신버전이 같은 DB·같은 Redis 를
보면서 동시에 실사용자 요청을 처리하는 구간**이 생깁니다. 아래 4건은 그 구간을
안전하게 만들기 위한 것입니다.

---

### 1. 하위호환(expand/contract) 마이그레이션 규율 — 팀 합의

**무엇을**: DB 스키마 · Redis 에 저장하는 객체의 직렬화 형식 · API 응답 · 이벤트 스키마 등
**두 버전이 공유하는 계약은 전부 "더하기만" 하는 방식**으로 바꾸는 규율에 합의해 주세요.

파괴적 변경(컬럼 삭제·이름 변경·타입 변경 등)은 여러 릴리스로 나눕니다:

```
추가 → 양쪽에 쓰기 → 기존 데이터 채우기 → 읽기 전환 → 옛 쓰기 중단 → 삭제
```

**왜**: 신버전이 컬럼을 지우는 순간, 아직 살아서 요청을 받고 있는 구버전 태스크가 깨집니다.

**함께 확인 부탁드립니다**: **마이그레이션이 앱 부팅과 분리되어 있는지**.
태스크마다 뜰 때 스키마를 바꾸면 롤링 중 여러 태스크가 동시에 마이그레이션을 시도합니다.

**알려주실 것**
1. 이 규율에 합의하셨는지 (합의 문서나 위키가 생기면 링크)
2. 현재 마이그레이션이 앱 부팅 시점에 실행되는지 / 별도로 실행되는지

---

### 2. readiness 와 liveness 분리

**무엇을**: `management.endpoint.health.probes.enabled=true` 를 켜고,
`/actuator/health/readiness` 가 **DB·Redis 연결 상태를 반영**하도록 해 주세요.

**왜**: 지금은 ALB 헬스체크와 컨테이너 헬스체크가 **둘 다 `/actuator/health`** 로 구분이 없습니다.
JVM 이 떴지만 아직 DB 에 붙지 못한 태스크에 ALB 가 트래픽을 보내면 그대로 5xx 가 됩니다.
블루/그린에서는 트래픽 전환 전에 충분히 기다릴 수 있었지만, 롤링은 헬스체크 통과가
곧 트래픽 유입입니다.

**확인 방법**: 앱 기동 직후 readiness 가 `OUT_OF_SERVICE` 였다가 의존성 연결 후 `UP` 으로
바뀌는지 봐 주시면 됩니다.

**알려주실 것**
3. 위 설정 적용 가능한지, 가능하다면 대략 언제쯤
4. readiness 에 포함시킬 의존성 목록 (DB · Redis 외에 더 있는지)

---

### 3. Graceful shutdown

**무엇을**: `server.shutdown=graceful` 과 `spring.lifecycle.timeout-per-shutdown-phase` 값을
확정해 주세요.

**왜**: 롤링은 구 태스크를 계속 내립니다. SIGTERM 을 받은 뒤 **신규 요청은 거부하되
처리 중이던 요청은 끝내고** 종료해야, 배포할 때마다 요청 몇 개가 잘리는 일이 없습니다.

**확인 방법**: 로컬에서 SIGTERM 을 보낸 뒤 처리 중이던 요청이 완료되는지, 신규 요청은
거부되는지 재현해 보시면 됩니다.

**알려주실 것**
5. 현재 `server.shutdown` 설정값 (기본값 `immediate` 인지)
6. 적용 후 `timeout-per-shutdown-phase` 를 얼마로 두실 것인지

---

### 4. 드레이닝 시간 값 정렬 — **인프라와 함께 정합니다**

**무엇을**: 아래 세 값을 **서로 맞물리게** 정해야 합니다. 두 개는 저희 쪽, 하나는 앱 쪽입니다.

ECS 는 이 순서로 태스크를 내립니다:

```
ALB 타깃 등록 해제 → [deregistration delay 동안 대기: 태스크는 살아서 요청 처리]
  → SIGTERM → [Spring graceful 동안 in-flight 완료] → [stopTimeout 지나면 SIGKILL]
```

| 값 | 주체 | 현재 | 만족해야 할 관계 |
|---|---|---|---|
| ALB `deregistration_delay` | 인프라 | **미설정 = 기본 300초** | ≥ 가장 긴 정상 요청 시간 |
| Spring `timeout-per-shutdown-phase` | **앱** | 확인 필요 (A-3) | < `stopTimeout` |
| ECS `stopTimeout` | 인프라 | 30초 | > Spring graceful |

**지금 정렬되어 있지 않습니다** — ALB 가 아직 드레이닝 중인데 컨테이너가 SIGKILL 될 수 있습니다.

**참고로 저희가 가진 숫자**: 최근 7일 prod 단일 요청 최대 소요는 **16.7초**
(`/api/v1/me`) 였고, p99 는 평상시 0.24~0.42초입니다. 이 값이면 예를 들어
**dereg 30초 / Spring graceful 20초 / stopTimeout 60초** 가 관계를 만족합니다.

**알려주실 것**
7. **16.7초보다 오래 걸리는 것이 정상인 API 가 있는지** (파일 업로드·리포트 생성·외부 결제 대기 등).
   있다면 그 최대 소요 시간 — 이 값이 `deregistration_delay` 의 하한을 정합니다
8. 위 예시 값(30 / 20 / 60)에 이견이 있으신지

---

## 3. 회신

번호(1~8)에 맞춰 답해 주시면 됩니다. **전부 한 번에 주실 필요는 없습니다** —
4건이 다 갖춰져야 착수하므로 각각 준비되는 대로 알려 주시면 됩니다.

판단이 어려운 항목은 "잘 모르겠다"고만 해주셔도 저희가 함께 확인하겠습니다.

---

## 4. 회신 (groble-backend, 2026-09-01)

번호대로 답합니다. **결론부터: 3번(graceful shutdown)은 이미 되어 있고, 2번(readiness 분리)은
설정만 넣으면 되며, 1번과 4번에 이견·추가 조건이 있습니다.** 그리고 **요청서에 없던 차단 후보 1건**을
§4-5 에 적었습니다.

| 항목 | 상태 | 한 줄 요약 |
|---|---|---|
| 1. expand/contract | 🔄 **합의. 단 마이그레이션은 부팅에 붙어 있다** | 분리는 하지 않고 "긴 ALTER 는 배포에 싣지 않는다" 규율로 간다 |
| 2. readiness/liveness | ✅ **가능. Phase 6 착수 전 반영** | 인프라 쪽 3건(ALB 경로·ECS 경로·WAF)이 세트로 필요하다 |
| 3. graceful shutdown | ✅ **이미 적용돼 있다** | `graceful` / `20s` 둘 다 dev·prod 에 명시돼 있다. 단 종료 대기가 20초로 안 끝난다 |
| 4. 드레이닝 값 | ⚠️ **예시 값에 이견** | **dereg 60 / graceful 20 / stopTimeout 90** 을 제안한다 |
| (추가) 스케줄러 다중 실행 | ⚠️ **저희 숙제** | 배치 23개에 분산 락이 없다. 착수 전 전수 점검하겠다 |

---

### 4-1. 하위호환(expand/contract) 마이그레이션 규율 — 답변 ①②

**① 합의합니다.** 다만 "이미 그렇게 하고 있었다"가 아니라 **지금부터 바뀌는 것**이라 솔직히 적습니다.

스키마는 Flyway 단방향으로만 갑니다(`ddl-auto: validate` · `clean-disabled: true` ·
`validate-on-migrate: true` — 앱이 스키마를 만들지 않습니다). 그런데 **파괴적 변경을 한 릴리스에
몰아넣는 것을 지금까지 막지 않았습니다.** 마이그레이션 229건 중:

| 유형 | 파일 수 | 최근 사례 |
|---|---|---|
| `DROP COLUMN` / `DROP TABLE` | 10 | `V20260328_03__drop_old_coupon_tables.sql` (2026-03-28) |
| `MODIFY COLUMN` | 24 | `V20260820_01__widen_purchases_cancel_reason_to_varchar.sql` |
| `DROP INDEX` | 11 | — |
| `RENAME COLUMN` / `CHANGE COLUMN` / `RENAME TABLE` | **0** | — |

블루/그린은 구·신이 동시에 트래픽을 받지 않으니 문제가 없었습니다. 롤링에서는 안 됩니다.

**확정하는 규율** — 요청서의 `추가 → 양쪽 쓰기 → 백필 → 읽기 전환 → 옛 쓰기 중단 → 삭제` 를 그대로 따르되,
판정이 갈리는 것들을 미리 정해 둡니다.

| 변경 | 단일 릴리스 허용 | 이유 |
|---|---|---|
| 컬럼·테이블·인덱스 **추가** | ✅ | 구버전이 모른 채로 동작한다 |
| `VARCHAR` **길이 확대**, `NOT NULL → NULL` | ✅ | 확장 방향이라 구버전이 깨지지 않는다. 최근 `MODIFY COLUMN` 은 대부분 이것이다 |
| 컬럼 **삭제·이름 변경·타입 변경·축소** | ❌ 릴리스 분리 | 구버전이 즉시 깨진다 |
| `NULL → NOT NULL` | ❌ 2단계 | nullable 추가 → 백필 → 다음 릴리스에서 제약 |
| Redis 저장 객체 직렬화 형식 변경 | ❌ 릴리스 분리 | 결제 멱등키·재고 예약이 여기 있어 구버전이 못 읽으면 결제 사고가 된다 |
| API 응답 필드 삭제·의미 변경 | ❌ | FE 계약이므로 원래도 분리 대상 |

**② 마이그레이션은 앱 부팅에 붙어 있습니다. 분리되어 있지 않습니다.**
`spring.flyway.enabled: true` 라 태스크가 뜰 때마다 Flyway 가 돕니다.

- **중복 적용은 나지 않습니다.** `flyway-mysql` 이 물려 있어 MySQL 세션 잠금으로 직렬화됩니다 —
  태스크 2개가 동시에 부팅해도 한쪽이 대기합니다.
- **대신 두 번째 태스크의 기동이 마이그레이션 시간만큼 밀립니다.** ECS `startPeriod` 가 120초라
  (`modules/services/production/api-service/main.tf`), 마이그레이션 + 스프링 기동이 그 안에 끝나야 합니다.

**분리(배포 파이프라인의 별도 단계로 Flyway 실행)는 이번 범위에서 하지 않겠습니다.** CD 워크플로에
마이그레이션 전용 태스크를 넣어야 하는 일이라 Phase 6 보다 큽니다. 대신 규율로 대체합니다:

> **대용량 테이블의 긴 `ALTER` 는 배포에 싣지 않는다.** 별도 창에서 손으로 선적용하고,
> 마이그레이션 파일은 이미 적용된 상태에서도 통과하도록 작성한다.

분리가 필요하다고 보시면 **별건 트랙**으로 잡아 주세요. 롤링의 차단 조건은 아니라고 판단합니다.

---

### 4-2. readiness / liveness 분리 — 답변 ③④

**③ 가능합니다. Phase 6 착수 전에 넣겠습니다.**
([RDS 8.4 호환성 회신](closed/rds-mysql-84-compatibility.md#6-회신-결과-2026-08-28)에서 "요청 시 즉시 진행"으로
답해 둔 건과 같은 것입니다.)

```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true          # ECS 는 K8s 자동감지가 안 되므로 명시가 필요하다
      show-details: never      # 현행 유지 (무인증 노출)
      group:
        readiness:
          include: readinessState, db, redis
        liveness:
          include: livenessState
  health:
    mail:
      enabled: false           # ↓ 아래 설명
```

**④ readiness 에 넣을 의존성은 `db` · `redis` 둘뿐입니다.**

| 의존성 | 포함 | 근거 |
|---|---|---|
| `db` | ✅ | HikariCP `connection-timeout: 30000`. 커넥션을 못 잡으면 30초 뒤 실패한다 — 그 사이 들어온 요청은 전부 5xx |
| `redis` | ✅ | 결제 멱등키·재고 예약·체크아웃 세션이 Redis 에 있다. Redis 없이 뜬 태스크가 결제를 받으면 **중복 결제·초과 판매**가 된다 |
| `mail` | ❌ **오히려 지금 꺼야 합니다** | 아래 |
| `diskSpace`, `ssl`, `ping` | ❌ | 노드 공용 자원이거나 무의미하다 |

> ⚠️ **`mail` 은 롤링과 무관하게 지금 살아 있는 위험입니다.**
> `spring-boot-starter-mail` 이 있어 `MailHealthIndicator` 가 자동 등록돼 있고, 이것이
> **`/actuator/health` 를 부를 때마다 SMTP 에 실제로 접속합니다.** 지금 ALB(30초)와 컨테이너
> 헬스체크(30초)가 둘 다 이 경로를 치므로 **30초마다 SMTP 커넥트 2회**가 나가고,
> **SMTP 가 흔들리면 DB·Redis 가 멀쩡해도 태스크가 죽습니다.**
> 2026-07-26 RDS 유지보수 때 "ALB 헬스체크가 태스크를 죽인 선례"와 같은 계열입니다.
> 같은 PR 에서 `management.health.mail.enabled: false` 로 끄겠습니다.

**⚠️ 인프라 쪽에 세트로 부탁드릴 것 3건 — 이게 분리의 나머지 절반입니다.**

| # | 무엇을 | 어디를 |
|---|---|---|
| **I-1** | ALB 타깃그룹 헬스체크 경로 → **`/actuator/health/readiness`** | `environments/{shared,dev,prod}/variables.tf` 의 `health_check_path` 기본값 |
| **I-2** | ECS 컨테이너 `healthCheck` → **`/actuator/health/liveness`** | `modules/services/{production,development}/api-service/main.tf:101` |
| **I-3** | WAF `ActuatorProtection` 예외를 `EXACTLY "/actuator/health"` → **`STARTS_WITH "/actuator/health"`** | `modules/security/waf/main.tf:219` |

- **I-1 과 I-2 는 반드시 같이 가야 합니다.** 지금은 둘 다 `/actuator/health` 입니다.
  readiness 에 db·redis 를 넣어 놓고 **컨테이너 헬스체크가 같은 경로를 계속 보면, DB 순단에
  ECS 가 전 태스크를 재시작합니다.** 분리의 핵심 효과가 정확히 이 지점입니다 —
  "빠진다(ALB)"와 "죽는다(ECS)"를 갈라 놓는 것.
- **I-3 은 당장의 장애는 아닙니다.** 규칙이 `count` 모드이고 ALB 헬스체크는 WAF 를 타지 않기
  때문입니다. 다만 지금 상태로는 `/actuator/health/readiness` 가 규칙에 걸려
  **외부에서 수동 확인이 안 되고**, 규칙을 block 으로 올리는 순간 문제가 됩니다.

**확인 방법**: 요청서대로 기동 직후 `OUT_OF_SERVICE` → 의존성 연결 후 `UP` 전이를 dev 에서 먼저 봅니다.

---

### 4-3. Graceful shutdown — 답변 ⑤⑥

**⑤ 이미 `graceful` 입니다. 기본값 `immediate` 가 아닙니다.**
`server.shutdown: graceful` — `application-prod.yml:137`, `application-dev.yml:136`.
주석까지 "SIGTERM 시 in-flight 대기"로 달려 있습니다.

**⑥ 이미 20초입니다.**
`spring.lifecycle.timeout-per-shutdown-phase: 20s` — `application-prod.yml:17`, `application-dev.yml:17`.
주석이 "ECS stopTimeout(기본 30s) 안에 정상 종료 완료 보장"이라, **정확히 이 목적으로 넣은 값**입니다.

> ⚠️ **그런데 종료가 20초에 안 끝납니다. 이게 4번 항목의 답을 바꿉니다.**
>
> `server.shutdown=graceful` 은 **웹 요청만** 기다립니다. 이 앱에는 그 뒤에 붙는 것이 둘 더 있습니다.
>
> | 대상 | 종료 대기 | 위치 |
> |---|---|---|
> | 웹 요청 (graceful) | ≤ 20초 | `spring.lifecycle.timeout-per-shutdown-phase` |
> | `mailExecutor` | **≤ 30초** | `AsyncConfig.java:60-61` (`setWaitForTasksToCompleteOnShutdown(true)` + `setAwaitTerminationSeconds(30)`) |
> | `webhookExecutor` | **≤ 30초** | `AsyncConfig.java:82-83` |
>
> **이 두 대기는 `timeout-per-shutdown-phase` 와 별개 타이머입니다.** 큐가 비어 있으면 즉시
> 끝나므로 평시에는 드러나지 않지만, **웹훅 큐가 밀린 상태에서 배포하면 `stopTimeout` 30초를
> 넘겨 SIGKILL 이 납니다.** (유실은 아닙니다 — `WebhookRetryScheduler` 가 30초마다 재시도합니다.
> 지연입니다.)
>
> 겹치는지 직렬인지는 요청서에 적어 주신 방법대로 **로컬 SIGTERM 으로 실측해서 확정**하겠습니다.
> 아래 §4-4 의 값은 **최악(직렬)을 가정**하고 냈습니다.

---

### 4-4. 드레이닝 시간 값 정렬 — 답변 ⑦⑧

**⑦ 16.7초보다 오래 걸리는 것이 정상인 API, 있습니다. 두 종류입니다.**

| API | 정상 상한 | 근거 |
|---|---|---|
| **멀티파트 업로드** — 콘텐츠 파일·상세이미지·어드민 영상 | **수십 초 ~ 2분** | 파일이 **서버를 통과합니다**(`MultipartFile`, presigned 직행이 아닙니다). `max-file-size: 60MB` 이고, 60MB 를 5Mbps 회선에서 올리면 전송만 ~96초입니다. `server.tomcat.connection-timeout: 120000` 과 `spring.mvc.async.request-timeout: 120s` 로 **이미 2분대를 상정해 둔 경로**입니다. 가장 긴 것은 어드민 영상 업로드(`AdminArticleController:288`) |
| **결제 승인** — `/api/v1/payments/**` | **최대 ~30초** | Payple 왕복을 **2번** 합니다: `payAuth` → `payAppCard`/`paySimplePayment` (`PaypleApiClient:69, 188, 239`). HTTP 어댑터가 connect 5초 + read 10초(`DefaultHttpClientAdapter:35-36`)라 **콜당 15초, 합 30초가 상한**입니다. 재시도 증폭은 없습니다 — `ResilientHttpClientAdapter`(retry 3회)는 빈으로만 존재하고 `DefaultHttpClientAdapter` 가 `@Primary` 라 실제로 주입되지 않습니다 |

그 밖은 16.7초 안에 들어옵니다. 판매내역 Export 는 동기 XLSX 생성이지만 **10,000행 상한 + 동시 3건
세마포어**(`SellContentExportService:39-40`)라 수 초대이고, 스케줄러·배치는 HTTP 요청이 아니라
드레이닝과 무관합니다.

**⑧ 예시 값(30 / 20 / 60)에 이견이 있습니다. 아래를 제안합니다.**

| 값 | 주체 | 제안 | 이유 |
|---|---|---|---|
| ALB `deregistration_delay` | 인프라 | **60초** | 결제 승인 상한 30초를 덮어야 한다. 30초로 두면 PG 가 느린 순간에 배포했을 때 승인 요청이 잘리는데, 이건 "요청 몇 개 실패"가 아니라 **승인 결과 불명(UNKNOWN)** 상태를 만든다 |
| Spring `timeout-per-shutdown-phase` | **앱** | **20초 유지** | 이미 그 값이고 관계를 만족한다 |
| ECS `stopTimeout` | 인프라 | **90초** | graceful 20초 뒤에 executor 대기가 붙는다(§4-3). 60초로는 웹훅 큐가 밀린 배포에서 SIGKILL 이 난다 |
| `mailExecutor` · `webhookExecutor` `awaitTerminationSeconds` | **앱** | 30 → **20초** (같은 PR 에서 내리겠습니다) | 20 + 20 + 20 = 60초 ≤ stopTimeout 90초. 여유 30초 |

관계 확인: `dereg 60` ≥ 결제 승인 상한 30초 · `graceful 20` < `stopTimeout 90` · 총 종료 최악 60초 < 90초.

> **업로드는 이 값으로도 잘립니다. 이건 의도적으로 받아들이자고 제안합니다.**
>
> - 업로드 실패는 조용하지 않고(에러 응답), 사용자가 즉시 재시도할 수 있습니다.
> - 덮으려면 dereg 를 150초 이상 둬야 하는데, 그러면 **태스크 1개 교체에 2.5분**이라
>   롤링의 배포 시간이 통째로 늘어납니다. 롤링으로 바꾸는 이유와 충돌합니다.
> - **근본 해법은 업로드를 presigned URL 직행으로 빼는 것**이고, 코드는 이미 있습니다
>   (`S3FileStorageService` presign — MCP 레인에서 쓰고 있습니다). 웹 업로드 경로도 옮기면
>   **dereg 를 30초까지 내릴 수 있습니다.** 별건 트랙으로 제안드립니다.

---

### 4-5. 요청서에 없던 항목 — 저희가 먼저 알려드립니다

**A. 스케줄러가 태스크마다 돕니다. 이게 4건보다 클 수 있습니다.**

`@Scheduled` 가 23개인데(부팅 시 `event=scheduled_inventory` 로그로 전수 목록이 남습니다)
**분산 락(ShedLock 류)이 없습니다.** 태스크가 2개가 되면 모든 배치가 2번 실행됩니다.

- **결제성 배치는 이미 다중 인스턴스를 전제하고 있습니다.**
  `SubscriptionBillingJobService.prepareBillingContext` 가 `findWithLockingById`
  (= `SELECT … FOR UPDATE`) 안에서 `canAttemptBilling` 을 다시 보고 시도 시각을 선커밋합니다
  (`SubscriptionBillingJobService.java:349-389`). 뒤에 온 인스턴스는 `SKIPPED` 로 빠집니다.
  코드 주석에도 "스케줄러 동시 실행 시 뒤에 온 인스턴스가…" 대비가 명시돼 있습니다(같은 파일 404-405행).
- **하지만 23개를 전수 검증하지는 않았습니다.** 정산 알림·이메일 리마인더·통계 집계 쪽은
  중복 발송·중복 집계 가능성이 남아 있습니다.
- **Phase 6 착수 전에 23개를 전수 점검하겠습니다.** 이건 저희 숙제입니다. 결과에 따라
  일부에 분산 락을 넣거나 단일 태스크 전용으로 뺍니다.
- ⚠️ 참고로 **블루/그린에서도 배포 중 짧게 2태스크가 겹칩니다.** 새로 생기는 위험이 아니라
  상시화되는 위험입니다.

**B. JVM 내 상태 1건 — 문제는 아닙니다.**
`SellContentExportService` 의 `Semaphore(3)` 는 프로세스 내 값이라 태스크 2개면 동시 export 가
6건이 됩니다. 월 한도는 DB 로 세므로(`SellListExportLogRepository`) 정합성 문제는 없고 부하만 2배입니다.
그대로 둬도 된다고 봅니다.

**C. 그 밖의 공유 상태는 안전합니다.**
세션(`RedisActiveSessionStore`)·멱등키·재고 예약·승인 락(`RedisApprovalLockAdapter`)이 전부
Redis 에 있어 태스크 증설 자체는 문제가 없습니다.

---

### 4-6. 저희 쪽 작업 순서

| # | 작업 | 묶음 |
|---|---|---|
| 1 | readiness/liveness 분리 + `management.health.mail.enabled: false` | PR ① |
| 2 | `mailExecutor`·`webhookExecutor` `awaitTerminationSeconds` 30 → 20 | PR ① (같이) |
| 3 | 로컬 SIGTERM 실측 — 총 종료 시간이 60초 안에 드는지 확인 | PR ① 검증 |
| 4 | **스케줄러 23개 다중 실행 안전성 전수 점검** | 별도, **가장 오래 걸립니다** |
| 5 | expand/contract 규율 문서화 (§4-1 표를 백엔드 위키에) | 별도 |

**4번이 끝나야 착수해도 안전하다고 봅니다.** 1~3 은 dev 먼저 올려 확인하겠습니다.

**인프라 쪽에서 답을 주셔야 진행되는 것**: §4-2 의 **I-1 · I-2 · I-3**, 그리고 §4-4 의
**dereg 60 / stopTimeout 90** 에 동의하시는지. 특히 **I-1 과 I-2 는 저희 PR 과 같은 시점에
나가야** 합니다 — 앱만 먼저 바꾸면 아무것도 안 바뀌고, 인프라만 먼저 바꾸면
`/actuator/health/readiness` 가 없어 전 태스크가 unhealthy 가 됩니다.

---

## 5. 인프라 회답 (groble-infra, 2026-09-02)

**§4 잘 받았습니다.** 특히 3번이 이미 되어 있다는 것과, executor 종료 대기·`MailHealthIndicator`·
스케줄러처럼 **저희가 묻지 않은 것을 찾아 주신 것**이 이 회신의 가치입니다.

I-1~I-4 에 답하고, 코드를 확인하는 과정에서 **정정할 것 2건**이 나와 함께 적습니다.

| # | 회답 | 한 줄 |
|---|---|---|
| **I-1** ALB 경로 → readiness | ✅ 동의. **단 위치가 다릅니다** | 유효한 곳은 shared 1곳이고, 타깃그룹 4개가 변수를 공유해 **선행 리팩터가 필요합니다** |
| **I-2** ECS `healthCheck` → liveness | ✅ 동의 | 모듈이 환경별로 갈려 있어 dev 만 먼저 가능합니다 |
| **I-3** WAF `STARTS_WITH` | ✅ 동의 | `count` 모드라 순서 제약이 없어 언제든 넣습니다 |
| **I-4** dereg 60 / stopTimeout 90 | ✅ 동의. **단 stopTimeout 은 태스크 정의로 넣습니다** | 지금 값은 노드 `user_data` 에 있어 노드를 갈지 않으면 안 바뀝니다 |
| "앱 PR 과 같은 시점에 나가야 한다" | ⚠️ **그럴 필요 없습니다 — 앱이 먼저가 더 안전합니다** | §5-5 |

---

### 5-1. I-1 정정 — 고쳐야 할 곳은 `shared` 한 곳이고, 그 전에 리팩터가 필요합니다

**① 지목해 주신 3곳 중 실제로 동작하는 것은 `shared` 뿐입니다.**

타깃그룹 5개는 전부 `environments/shared` 가 만듭니다. prod·dev 환경은 `load-balancer` 모듈을
호출하지 않고, 만들어진 타깃그룹의 ARN 만 remote state 로 받아 씁니다.

```
environments/shared/main.tf:62   health_check_path = var.health_check_path
  └→ modules/infrastructure/load-balancer/main.tf
       39: prod_blue_tg   path = var.health_check_path
       67: prod_green_tg  path = var.health_check_path
       99: dev_blue_tg    path = var.health_check_path
      127: dev_green_tg   path = var.health_check_path
      170: monitoring_tg  path = "/api/health"   ← 하드코딩이라 별개
```

⚠️ **`environments/{prod,dev}/variables.tf` 의 `health_check_path` 는 어느 모듈에도 연결되어
있지 않습니다.** `terraform.tfvars` 에 값이 들어 있지만 소비자가 없습니다. **고치고 apply 해도
plan 에 아무것도 뜨지 않습니다** — "적용했다"고 착각하기 쉬운 자리라 저희 쪽에서 주석으로
표시해 두겠습니다.

**② 더 중요한 것: 지금 구조로는 dev 만 바꿀 수 없습니다.**

위에서 보시듯 **타깃그룹 4개가 `var.health_check_path` 하나를 공유**합니다.
`shared` 의 값을 readiness 로 바꾸면 **prod blue/green 도 같이 바뀝니다.**

```
[앱] PR① 이 dev 에만 배포된 상태에서 인프라가 경로를 바꾸면

  ALB → prod 태스크  GET /actuator/health/readiness → 404
      → matcher "200-399" 불일치
      → prod TG 는 unhealthy_threshold 2 × interval 30 = 60초 뒤 unhealthy
      → ALB 가 prod 타깃을 전부 제외  ⛔ prod 전면 5xx
```

말씀하신 "인프라만 먼저 바꾸면 전 태스크가 unhealthy 가 된다"가 **dev 만 바꾸려 할 때도
prod 에서 일어난다**는 뜻입니다.

**③ 그래서 선행 작업을 하나 넣습니다 — 값은 하나도 바꾸지 않는 리팩터입니다.**

`load-balancer` 모듈의 변수를 환경별로 쪼갭니다.

| | 지금 | 리팩터 직후 |
|---|---|---|
| prod TG 경로 | `var.health_check_path` = `/actuator/health` | `var.prod_health_check_path` = `/actuator/health` |
| dev TG 경로 | `var.health_check_path` = `/actuator/health` | `var.dev_health_check_path` = `/actuator/health` |

**두 값이 지금과 같으므로 `terraform plan` 은 No changes 여야 하고, 그것을 prod 무영향의
증거로 삼습니다.** 이후 dev 변수만 올리면 **dev 타깃그룹 2개만** 움직입니다.

`deregistration_delay`(I-4) 도 지금 4개 타깃그룹 전부 미설정이라 같은 문제가 있어,
같은 리팩터에서 함께 쪼갭니다.

---

### 5-2. I-2 동의 — 그리고 `mail` 지적은 prod 에서 더 급합니다

[`prod:101`](../../modules/services/production/api-service/main.tf) ·
[`dev:101`](../../modules/services/development/api-service/main.tf) 확인했습니다. 지목하신 위치가 정확하고,
**이쪽은 모듈이 환경별로 갈려 있어 dev 만 먼저 바꿀 수 있습니다.**

"readiness 에 db·redis 를 넣어 놓고 컨테이너 헬스체크가 같은 경로를 계속 보면 DB 순단에
ECS 가 전 태스크를 재시작한다"— 정확합니다. 저희가 놓치고 있던 지점입니다.

> ⚠️ **`MailHealthIndicator` 건은 prod 가 dev 보다 먼저 터집니다.** 타깃그룹 민감도가 다릅니다.
>
> | | `unhealthy_threshold` | `timeout` | 실패 판정까지 |
> |---|---|---|---|
> | prod blue/green | **2** | 5초 | **60초** |
> | dev blue/green | 5 | 8초 | 150초 |
>
> SMTP 가 흔들릴 때 **prod 는 60초 만에 타깃에서 빠집니다.** `management.health.mail.enabled: false`
> 를 PR① 에 넣어 주시는 것에 전적으로 동의하고, **이 항목만은 dev 검증을 기다리지 말고
> prod 에도 빨리 반영**하는 편이 낫다고 봅니다. 롤링과 무관하게 지금 열려 있는 위험입니다.

---

### 5-3. I-3 동의

현재 규칙은 `CONTAINS "/actuator/"` **AND NOT** `EXACTLY "/actuator/health"` → `count`
([`modules/security/waf/main.tf:222`](../../modules/security/waf/main.tf)) 입니다.
`STARTS_WITH` 로 바꾸면 `/actuator/health/readiness` · `/liveness` 가 함께 예외가 됩니다.

`count` 모드이고 ALB 헬스체크는 WAF 를 타지 않아 **순서 제약이 없으므로**, 위 리팩터와 같이
넣겠습니다. block 으로 올릴 때를 대비한다는 판단에 동의합니다.

---

### 5-4. I-4 동의 — 값은 그대로, `stopTimeout` 적용 방법만 다릅니다

**dereg 60 / graceful 20 / stopTimeout 90 에 동의합니다.** 결제 승인 상한 30초와
executor 종료 대기라는 두 근거가 저희 예시값(30/20/60)보다 정확합니다.
특히 "잘린 승인은 실패가 아니라 **결과 불명(UNKNOWN)**" 이라는 지적이 결정적이었습니다.

**① `stopTimeout` 은 태스크 정의에 넣겠습니다. 지금 그 필드가 아예 없습니다.**

| 위치 | 현재 |
|---|---|
| 태스크 정의 `stopTimeout` | **없음** (prod·dev 둘 다) |
| `prod_user_data.sh:25` | `ECS_CONTAINER_STOP_TIMEOUT=30s` |
| `dev_user_data.sh` | **그 줄이 아예 없음** — 에이전트 기본값 30초라 결과는 같습니다 |

즉 지금의 30초는 **노드 설정**이고, `user_data` 는 `lifecycle` 때문에 **고쳐도 실행 중 노드에
반영되지 않습니다.** 90초를 노드로 넣으면 노드 교체가 필요해집니다.

→ **태스크 정의의 `stopTimeout = 90` 으로 넣습니다.** 노드를 갈지 않아도 되고, 모듈이
환경별로 갈려 있어 **dev 먼저**가 가능합니다.
(태스크 정의 값이 에이전트 설정을 이기는지는 **dev 에서 실측 확인**하겠습니다.)

**② `dereg 60` 은 현행 대비 보호를 줄이는 변경입니다 — 상호 확인만 남깁니다.**

지금 4개 타깃그룹은 `deregistration_delay` **미설정 = 기본 300초**입니다. 60초는 **내리는**
방향이고, 그래서 **지금은 살아남는 업로드가 앞으로는 잘립니다.**

| | 업로드에 주어지는 시간 | 60MB / 5Mbps ≈ 96초 |
|---|---|---|
| 지금 (dereg 300 + graceful 20) | 320초 | ✅ 완료 |
| 앞으로 (dereg 60 + graceful 20) | 80초 | ❌ **잘림** |

§4-4 에서 **"의도적으로 수용"** 이라고 명시해 주셨으므로 그대로 진행하겠습니다.
근본 해법(presigned 직행)은 [`infra-future-improvements.md`](../plan/infra-future-improvements.md) 에
별건으로 등록하고, 전환되면 dereg 를 30초로 내리는 것에 동의합니다.

**③ 배포 시간에 미치는 영향을 함께 알아 둡니다.**

태스크 1개 교체가 **최악 dereg 60 + 종료 60 = 120초**입니다. desired 2 가 되는
[Phase 7](../runbook/phase-07-dev-cache-asg.md)(dev)·[9](../runbook/phase-09-prod-asg.md)(prod) 에서는
순차 교체라 배포 1회가 **최악 4분대**가 됩니다. 수용 가능하다고 보지만, 배포가 느려졌다는
인상이 생길 수 있어 미리 공유합니다.

---

### 5-5. "앱 PR 과 같은 시점" 은 필요 없습니다 — **항상 앱이 먼저입니다**

§4-6 마지막의 우려에 답합니다. **동시 배포를 조율하지 않으셔도 됩니다.**

| 순서 | 무슨 일이 일어나나 |
|---|---|
| **앱 먼저** | `/actuator/health/readiness` 가 **생기기만** 합니다. 아무도 그 경로를 보지 않으므로 무해합니다. `mail` 끄는 것은 즉시 이득입니다 |
| 인프라 먼저 | ALB 가 없는 경로를 보게 되어 **60초 뒤 전 태스크 unhealthy** ⛔ |

→ **앱 PR① 이 배포된 것을 확인한 뒤 저희가 경로를 옮깁니다.** 되돌리기도 저희 쪽 변수 한 줄이라
앱 롤백 없이 복구됩니다. 같은 시점에 맞추는 것보다 이쪽이 안전합니다.

---

### 5-6. 스케줄러 건 — 새 차단 조건으로 접수했습니다

**§4-5 A 를 5번째 착수 조건으로 올렸습니다.** 먼저 찾아 알려 주신 것에 감사드립니다.
"블루/그린에서도 배포 중 짧게 2태스크가 겹치므로 새로 생기는 위험이 아니라 상시화되는 위험"
이라는 정리에 동의합니다.

> 💡 **[`http-metrics-5xx-undercount.md`](./http-metrics-5xx-undercount.md) 의 B 항목과 같은 23개를 보고 있습니다.**
> 그쪽은 "스케줄러 정체 알람의 임계를 정하려면 중요도·실행 주기가 필요하다"는 요청인데,
> 지금 하시려는 전수 점검에서 **같은 표에 `실행 주기` · `중요도` · `다중 실행 안전성` 세 열을
> 함께 채워 주시면** 두 건이 한 번에 끝납니다.

§4-5 B(`Semaphore(3)` 가 태스크당) 는 그대로 두는 데 동의합니다.
C 는 저희 인식과 같습니다.

---

### 5-7. 정리 — 누가 언제 무엇을

| 순서 | 주체 | 작업 | 비고 |
|---|---|---|---|
| 1 | 인프라 | **타깃그룹 변수 환경별 분리** (경로 · dereg) + WAF `STARTS_WITH` | 값 불변. `plan` No changes 확인 |
| 2 | 앱 | **PR① dev 배포** (readiness/liveness · `mail` off · executor 20s) | 인프라보다 먼저 |
| 3 | 앱 | 로컬 SIGTERM 실측 → 총 종료 시간 공유 | `stopTimeout 90` 의 근거 확정 |
| 4 | 인프라 | **dev 만** 경로 → readiness · `healthCheck` → liveness · `stopTimeout 90` · dereg 60 | dev TG 2개만 움직임 |
| 5 | 공동 | dev 검증 (기동 직후 `OUT_OF_SERVICE` → `UP` 전이 확인) | |
| 6 | 앱 | PR① prod 배포 | |
| 7 | 인프라 | prod 동일 적용 | |
| 8 | 앱 | **스케줄러 23개 전수 점검** ← 가장 오래 걸림 | [Phase 6](../runbook/phase-06-deployment-controller.md) 착수의 마지막 조건 |

**⚠️ `mail` 끄는 것만은 위 순서와 무관하게 prod 에 빨리 반영해 주시길 부탁드립니다** (§5-2).

**저희가 기다리는 것**: 3번(SIGTERM 실측값)과 8번(스케줄러 점검 결과)입니다.
나머지는 저희 쪽에서 진행하겠습니다.
