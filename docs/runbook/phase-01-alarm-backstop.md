# Phase 1 — 알람 백스톱 확보

> [← Phase 0](./phase-00-terraform-state-s3.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 2 →](./phase-02-observability.md)

| | |
|---|---|
| **상태** | ✅ 완료 (2026-08-17). 잔여 항목 1건은 Phase 2로 이관 (워킹셋 측정) |
| **목적** | 이후 단계에서 문제가 생겼을 때 **자체 호스팅 관측이 죽어도 알림이 도달**해야 한다. Phase 6의 배포 자동 롤백도 이 알람에 의존한다 |
| **사용자 영향** | 없음 |
| **되돌리기** | 리소스 삭제 |

---

## ✅ 완료 요약

> **이 문서는 이미 끝난 작업의 기록이다.** 아래 절차는 다시 따라 할 것이 아니라, 지금 배포된 상태가
> 어떻게 만들어졌는지와 되돌리는 방법을 남겨둔 것이다.

- **배포된 것** — CloudWatch 알람 **19개** → SNS 토픽 2개 → AWS Chatbot(us-east-2) → Slack 2채널
  (`#groble-alert` 긴급 / `#groble-alert-dev`). 코드는 `modules/observability/{alerting,alb-alarms,rds-alarms}`.
  지표 비용 월 약 **$1.90**.
- **계획과 달랐던 점** — ① RDS 알람이 차원 오설정으로 **조용히 고장나 있던 것**을 검증 중에 발견·수정했다
  ② 임계치 6개를 실측 기준으로 조정·신설했다 ③ 지연 알람을 지속(p99 2초·15분)과 급증(p99 5초·1구간)
  **둘로 분리**했다 ④ dev 채널에는 `ok_actions`를 걸지 않았다(사건당 메시지가 2배가 되는 것을 피함).
- **다음으로 넘긴 것 1건** — prod API 태스크의 워킹셋 측정 → [Phase 2](./phase-02-observability.md).
  [Phase 8](./phase-08-prod-asg.md)의 `memory_reservation`이 이 값에 의존한다.
- **⚠️ 운영 주의** — Slack 채널 ID는 gitignore 대상인 `terraform.tfvars`에 있다.
  값이 비면 Chatbot 리소스가 `count = 0`으로 빠지면서 **Slack 연동이 조용히 삭제된다.**
- **롤백** — 리소스 삭제. 단 Chatbot IAM 역할은 Terraform이 지우지 못해 CLI 삭제가 필요할 수 있다.

---


## 구축 결과

### 알림 경로

```
CloudWatch 알람 → SNS(ap-northeast-2) → AWS Chatbot(us-east-2) → Slack
```

**채널을 긴급도로 나눴다.** 볼륨 때문이 아니라, "새벽에 깨야 하는 것"과 "내일 봐도 되는 것"이
같은 채널에 있으면 구분되지 않기 때문이다.

| 채널 | SNS 토픽 | 대상 | OK 통지 |
|---|---|---|---|
| `#groble-alert` | `groble-alerts-prod` | Prod, 모니터링 노드, ALB 전체 5xx, RDS | O |
| `#groble-alert-dev` | `groble-alerts-dev` | Dev | **X** |

Dev에 `ok_actions`를 걸지 않은 것은 사건당 메시지가 2배가 되는 것을 감수할 만큼 급하지 않기 때문이다.
복구 여부는 필요할 때 콘솔·CLI로 확인한다.

> **모니터링 노드 알람이 dev가 아니라 prod 채널로 가는 이유**:
> 이 노드가 private 서브넷의 NAT을 겸직하고 있어, 죽으면 prod의 아웃바운드와 ECR pull이 함께 끊긴다.
> [Phase 3](./phase-03-nat-gateway.md)(NAT Gateway)·[Phase 4](./phase-04-monitoring-node-rebuild.md)(노드 재구축)로
> 이 결합이 해소되면 dev 채널로 내린다.

### 알람 19개

| 알람 | 임계치 | 채널 |
|---|---|---|
| `groble-alb-elb-5xx` | 5분 10건 | prod |
| `groble-{prod,dev}-target-5xx` | prod **5분 1건** · dev 5분 10건 | 각 |
| `groble-{prod,dev}-latency-p99` | p99 **2초** · 15분 연속 (지속적 저하) | 각 |
| `groble-{prod,dev}-latency-p99-spike` | p99 **5초** · 1구간 (단발 급증) | 각 |
| `groble-{prod,dev,monitoring}-no-healthy-host` | 정상 타깃 합 < 1 · 5분 | prod/dev/prod |
| `groble-{prod,dev,monitoring}-unhealthy-host` | 비정상 타깃 합 > 0 · 5분 | prod/dev/prod |
| `groble-prod-rds-cpu` | 80% · 15분 | prod |
| `groble-prod-rds-cpu-credits` | 크레딧 < 30 | prod |
| `groble-prod-rds-connections` | > 60 | prod |
| `groble-prod-rds-storage` | < 4GiB | prod |
| `groble-prod-rds-memory` | **< 15MiB** (평소보다 악화 시) | prod |
| `groble-prod-rds-swap` | > 600MiB | prod |

**임계치는 전부 실측 근거로 확정했다.** 근거 수치는 각 모듈 변수의 description에,
전체 기준선은 [계획서 §2.1 "트래픽·자원 기준선"](../infra-ha-improvement-plan.md)에 있다.

**비용**: 지표 기준 29개 → 무료 10개 제외 시 **월 약 $1.90**

### 코드 위치

```
modules/observability/
  alerting/      # SNS 토픽 + Chatbot 설정 (채널마다 1회 호출)
  alb-alarms/    # ALB·타깃그룹 알람
  rds-alarms/    # RDS 알람
```

`environments/shared`에서 alerting 2벌 + alb-alarms, `environments/prod`에서 rds-alarms를 호출한다.
Slack 채널 ID는 `terraform.tfvars`에 있고 **이 파일은 gitignore 대상**이다 — 다른 사람이 apply하려면 별도 전달이 필요하며,
값이 비면 Chatbot 리소스가 `count = 0`으로 빠지면서 Slack 연동이 조용히 삭제된다.

---

## 구축 중 확인한 것 (재현·재검토 시 참고)

**AWS Chatbot은 ap-northeast-2에 없다.** API 엔드포인트가 us-east-2에만 존재해
(`chatbot.ap-northeast-2.amazonaws.com`은 연결 실패) 프로바이더 별칭이 필요하다.
반면 **CloudWatch 알람은 같은 리전의 SNS 토픽에만 발행할 수 있고, 다른 리전이면 에러 없이 조용히 실패한다.**
따라서 `알람·SNS = ap-northeast-2` / `Chatbot = us-east-2`가 **유일하게 성립하는 조합**이다.

**`HTTPCode_ELB_5XX_Count`에는 TargetGroup 차원이 없다** (LoadBalancer / AvailabilityZone 뿐).
이 알람만은 prod·dev 분리가 불가능해 합산값을 prod 채널로 보낸다.
`HTTPCode_Target_5XX_Count`와 `TargetResponseTime`은 TargetGroup 차원이 있어 서비스별로 분리했다.

**Blue/Green 타깃그룹은 배포마다 활성 쪽이 뒤바뀐다.** 특정 TG에 알람을 고정하면 스왑 직후부터
유휴 TG를 감시하게 되어 무의미해진다. 서비스에 속한 TG들을 metric math로 집계해 판정한다
(헬스·5xx는 `SUM`, p99는 백분위수라 더할 수 없으므로 `MAX`).
[Phase 6](./phase-06-deployment-controller.md)에서 단일 TG로 정리되면 이 구조는 단순해진다.

**Chatbot IAM 역할 삭제 시 권한 부족으로 막힌다.** provider가 삭제 전 `iam:ListInstanceProfilesForRole`을
호출하는데 SSO 역할에 그 권한이 없다(`iam:DeleteRole`은 있다). AWS CLI로 직접 삭제 후 `terraform state rm`으로 해소했다.
[Phase 10](./phase-10-access-path.md)에서 권한을 손볼 때 함께 추가하는 것을 검토한다.

**제자리 수정(in-place update)은 알림을 보내지 않는다.** CloudWatch는 **상태 전환**에만 통지하므로,
이미 `OK`인 알람의 설정만 바꾸면 메시지가 오지 않는다. 채널 분리 apply 후 신규 생성된 알람만 통지된 이유다.

### ⚠️ RDS 알람이 처음에 조용히 고장나 있었다

**`aws_db_instance.id`는 `DBInstanceIdentifier`가 아니라 `DbiResourceId`를 반환한다** (AWS provider 5.x).

```
잘못된 차원 : db-WM4VKRGNLYVHSHUBNSEJJM3AZ4   ← aws_db_instance.id
올바른 차원 : groble-prod-mysql               ← aws_db_instance.identifier
```

`rds-mysql` 모듈의 `rds_instance_id` output이 전자를 내보내고 있었고, 이름만 보고 CloudWatch 차원 값으로 썼다.
결과적으로 **존재하지 않는 지표를 감시하는 알람 5개**가 만들어졌다.

**이 실패는 어디에서도 에러를 내지 않는다.** `terraform apply`는 성공하고, 알람도 콘솔에 정상으로 보이며,
plan도 깨끗하다. 유일한 증상은 알람이 `INSUFFICIENT_DATA`에서 내려오지 않는 것뿐이다.
**"알람을 만들었다"와 "알람이 감시하고 있다"는 다른 상태다.**

→ `rds_instance_identifier` output을 추가해 해소했다. 기존 `rds_instance_id`는 다른 참조가 있을 수 있어
값을 바꾸지 않고 description에 경고를 남겼다.

> 이 사례가 아래 검증 항목 **"`INSUFFICIENT_DATA`로 방치되지 않는지"**가 형식적 절차가 아닌 이유다.
> 알람을 만든 뒤 **반드시 상태가 `OK`로 수렴하는 것까지 확인할 것.**
> 새 알람을 추가하는 모든 Phase에 적용된다.

---

### 알람이 첫날에 실제 문제를 찾았다

Prod RDS가 **만성적인 메모리 부족 상태**임이 실측으로 드러났다.

```
FreeableMemory  21~62 MiB (평균 42) / 총 1 GiB
SwapUsage       400~482 MiB, 7일간 안정된 고원
CPUUtilization  4.7~5.0%     CPUCreditBalance  288 (최대치)
```

**병목은 메모리 하나다.** 원인은 `innodb_buffer_pool_size`가 엔진 기본 공식
`{DBInstanceClassMemory*3/4}` ≈ 768 MiB로, 1 GiB 인스턴스에는 과하다는 것이다.

임계치를 100 → 15 MiB로 내린 것은 **문제를 덮은 것이 아니라**, 만성 상태를 정상선으로 인정하고
"평소보다 악화됨"을 감지하도록 알람의 역할을 바꾼 것이다. 만성 부족 자체는
`groble-prod-rds-swap` 알람과 아래 문서 항목이 추적한다.

→ 해소 방안과 실측 근거는 [`infra-future-improvements.md`의 High-4](../infra-future-improvements.md#high-4)에 있다.
**[Phase 7](./phase-07-elasticache.md) 진입 전에 결정한다** — Redis를 ElastiCache로 빼면 결제 경로가 DB에 더 의존한다.

---

### 임계치를 실측으로 확정했다

**1주를 기다리지 않았다.** CloudWatch는 ALB 지표를 5분 해상도로 63일, 1시간 해상도로 455일 보관한다.
알람 생성과 지표 수집은 무관하므로 **과거 7일 데이터로 기준선을 즉시 만들 수 있었다.**
런북 원문의 "1주일 관측한 뒤 확정"은 "과거 1주 데이터로 확정"이 정확하다.

| 알람 | 초기값 | 확정값 | 실측 근거 |
|---|---|---|---|
| `target-5xx` | 25건 | **10건** → prod 는 이후 **1건** (아래) | 5분 구간 최대 2건, 7일 합계 5건 |
| `latency-p99` | 5초 | **2초** | 평상시 p99 0.24~0.42초, p50 0.05초 |
| `latency-p99-spike` | — | **5초 / 1구간** | 신규 (아래) |
| `alb-elb-5xx` | 10건 | **유지** | 노이즈 1건 vs 사건 71건 — 잘 갈라진다 |
| RDS `memory` | 100 MiB | **15 MiB** | 실측 21~62 MiB |
| RDS `swap` | — | **600 MiB** | 실측 400~482 MiB 고원 |

### 🔴 prod `target-5xx` 를 10 → 1 로 내렸다 (2026-08-30)

**실측으로 잡은 10이 틀린 값이어서가 아니라, 그 임계가 담고 있던 전제가 운영 정책과 달랐다.**

10은 "평상시 최대(5분당 2건)의 5배 = 노이즈는 버리고 실제 이상만 잡는다"는 뜻이었다.
통계적으로는 타당하지만, **"500 은 한 건도 그냥 넘기지 않는다"** 는 정책과는 정면으로 어긋난다.
알람은 "500 이 심각한가"를 물은 적이 없고 "5 분에 10 건을 넘는가"만 물었다.

실제로 놓친 사건이 있다. 최근 14 일 prod 500 발생과 발화 여부:

| 발생 (KST) | 엔드포인트 | 앱 지표 | ALB 지표 | Slack |
|---|---|---|---|---|
| 08-17 20:04 | `POST /api/v1/market/edit` | 500 × 2 | 2건 | ❌ **안 울림** |
| 08-29 02:21~02:23 | `POST /api/v1/orders/create` · `POST /api/v1/content/track/{contentId}` | 500 × 4 | 8 + 2 = **10건** | ✅ 울림 (02:26) |

`groble-prod-target-5xx` 의 14 일간 발화 이력은 `2026-08-28T17:26:05Z` ALARM → `17:29:05Z` OK **단 1 건**이다.
08-29 건이 울린 것은 정렬된 5 분 구간에 8+2 가 합쳐져 정확히 10 에 닿았기 때문으로,
**한 건만 적었어도 침묵했다.**

Grafana R1(`groble-payment-5xx`)은 임계가 1 건이지만 **결제 URI 화이트리스트 전용**이라
위 두 엔드포인트를 모두 커버하지 않는다. 즉 **결제 경로 밖의 prod 500 은
5 분에 10 건 미만이면 어디서도 울리지 않는 상태였다.**

**조치** — `var.services[*].target_5xx_threshold` 를 새로 두어 서비스별로 재정의할 수 있게 하고,
prod 만 1 로 내렸다. dev 는 10 을 유지한다 (개발 중 500 은 흔하다).
예상 발화 빈도는 실측 기준 **주 1 건 남짓**이다.

#### 08-29 건의 실제 원인과, 함께 드러난 결함 2가지

Loki 로그로 사건의 정체를 확인했다. 10 건 전부 같은 예외다:

```
org.springframework.orm.jpa.JpaSystemException: could not execute statement
  [The MySQL server is running with the --read-only option so it cannot execute this statement]
```

**[RDS MySQL 8.4 Blue/Green 스위치오버](./adhoc/rds-mysql-84-upgrade.md) 창이었다.** 구 인스턴스가
read-only 로 바뀌었는데 앱이 계속 거기에 쓰고 있었다 — 그 런북이 기록한
*"DNS 는 정상이었다. JVM 이 구 IP 를 캐시한 것이다"* 가 이것이다.
17:23:16Z 의 수동 CodeDeploy 배포는 원인이 아니라 **JVM DNS 캐시를 털기 위한 조치**였다.

숫자가 맞아떨어진다:

| 출처 | 17:21 | 17:23 | 합계 |
|---|---|---|---|
| ALB `HTTPCode_Target_5XX_Count` | 8 | 2 | **10** |
| Loki `GlobalExceptionHandler` | 8 | 2 | **10** |
| Prometheus Micrometer | — | — | **4** |

> ⚠️ **초판의 가설은 틀렸다.** "Micrometer 필터 앞단에서 터졌거나 재기동 중 503" 으로 추정했으나,
> 10 건 모두 정상적으로 `http-nio-8080-exec-*` 스레드에서 `GlobalExceptionHandler` 를 거쳤다.
> 스레드 고갈도 없었고(live threads 56~62 안정), HikariCP pending 0, `/error`·`UNKNOWN` URI 도 없었다.

**결함 ① `increase()` 가 시계열의 첫 등장을 못 본다** — Micrometer 가 기록한 4 건 중
`POST /api/v1/orders/create` 2 건은 **R1 결제 알람의 화이트리스트 `/api/v1/orders/.+` 에 포함**되는데도
R1 이 침묵했다. 그 시계열이 `17:22:00Z` 에 값 2 로 처음 나타나 그대로 평평했기 때문이다.
→ [groble-images#12](https://github.com/TEAM-LIAISON/groble-images/pull/12) 에서 R1~R4 에
`+ (sum(M unless (M offset W)) or vector(0))` 항을 더해 수정했다.

**결함 ② 500 10 건 중 4 건만 `http_server_requests` 에 기록됐다** — 백엔드 계측 문제로,
원인 미확인이다. **감시 지표로는 ALB 쪽이 더 민감하다**는 뜻이기도 하다.
→ [`http-metrics-5xx-undercount.md`](../handoff/http-metrics-5xx-undercount.md) 로 백엔드에 조사 요청했다.

### 지연 알람을 둘로 나눈 이유

**"임계치를 낮추면 잡힌다"가 성립하지 않는 경우가 있다.**

2026-08-13에 p99가 13:45에 **42.3초**, 19:50에 **6.5초**를 기록했다.
그런데 두 사건 모두 **단일 5분 구간**이었고, 그 외 1~3초대 초과도 연속되지 않았다.
`latency-p99`는 15분 연속을 요구하므로 **임계치를 2초로 낮춰도 이 사건들은 잡히지 않는다.**

→ 역할을 분리했다.

| 알람 | 조건 | 잡는 것 |
|---|---|---|
| `latency-p99` | 2초 · 15분 연속 | "시스템이 지금 느리다" — 지속적 저하 |
| `latency-p99-spike` | 5초 · 1구간 | "방금 뭔가 크게 잘못됐다" — 단발 급증 |

42초 p99는 일부 사용자가 42초를 기다렸다는 뜻이므로 놓칠 수 없다.
5초 임계치면 위 두 사건이 잡히고 7일간 그 외 오탐은 없다.

> ⚠️ `latency-p99-spike`는 [Phase 6](./phase-06-deployment-controller.md)(rolling)·[Phase 8](./phase-08-prod-asg.md)(instance refresh)
> 중에 울릴 수 있다. 전환 작업 중이라면 그 자체가 정보이지만, 오탐으로 느껴지면 작업 창에서만 임계치를 올릴 것.

8/13의 42초 지연에는 **5xx가 없었다** — 실패가 아니라 순수 지연이다.
RDS 스왑(450 MiB)과 cross-AZ 쿼리가 의심되지만 현재 데이터로 단정할 수는 없다.

---

## 남은 작업

### Phase 2로 이어지는 측정 하나

**prod API 태스크의 실제 워킹셋**을 아직 모른다. `AWS/ECS` 지표로는 사용량이
하드 리밋(1,500 MiB)의 91~100%로 보이는데, 14일간 OOM 킬이 0회였으므로
대부분이 회수 가능한 페이지 캐시로 판단된다. 그러나 **배치(placement)에 쓸 올바른
`memoryReservation` 값은 캐시를 제외한 워킹셋이어야 하고, 이는 cAdvisor의
`container_memory_working_set_bytes`로만 보인다 — Prometheus 접근이 필요하다.**

→ [Phase 2](./phase-02-observability.md)에서 Prometheus를 손볼 때 함께 측정한다.
[Phase 8](./phase-08-prod-asg.md)의 `memory_reservation` 결정(계획된 1000은 근거 없는 값)과
[Phase 9](./phase-09-dev-cache-asg.md)의 dev `memory = 900`이 이 측정에 의존한다.

상세는 [계획서 §2.1](../infra-ha-improvement-plan.md)에 있다.

---

## 검증

- [x] 알람을 수동으로 `ALARM` 상태로 전환해 **외부 채널까지 실제로 도달**하는지 확인
  - `#groble-alert`: 알람 생성 시 `OK` 전환으로 도달 확인
  - `#groble-alert-dev`: `set-alarm-state`로 강제 `ALARM` 전환해 도달 확인
- [x] 알람이 `INSUFFICIENT_DATA`로 방치되지 않는지 — 전체 `OK` 수렴 확인
- [x] SNS 토픽 2개 각각에 Chatbot 구독이 생성되었는지
- [x] 알람별 `alarm_actions`가 의도한 채널을 가리키는지 (실제 값 대조)
- [x] **알람 17개 전부 `OK`로 수렴** — RDS 차원 버그와 메모리 임계치 오설정을 이 검증으로 잡았다
- [x] **트래픽 기준선 표 작성** — CloudWatch 보관 데이터로 즉시 완료 (계획서 §2.1)
- [x] **임계치 실측 기반 확정** — 6개 조정/신설

## 롤백

리소스 삭제. 다른 단계에 영향 없다.
단, Chatbot IAM 역할은 위 권한 문제로 Terraform이 지우지 못하므로 CLI 삭제가 필요할 수 있다.

---

[← Phase 0 — Terraform state를 S3로 이전](./phase-00-terraform-state-s3.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 2 — 관측 선행 전환 →](./phase-02-observability.md)
