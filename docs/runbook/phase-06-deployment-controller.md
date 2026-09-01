# Phase 6 — 배포 컨트롤러 전환 (CodeDeploy → ECS rolling)

> [← Phase 4](./phase-04-monitoring-node-rebuild.md) · [이관 절차 목차](README.md) · [다음: Phase 7 →](./phase-07-dev-cache-asg.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | Blue/Green은 4슬롯 플릿에서 여유가 0이라 유지할 수 없다(계획서 §2.6) |
| **사용자 영향** | 없음 — 신 서비스가 준비된 뒤 리스너를 스왑한다 |
| **환경 순서** | **Dev 를 완주한 뒤 Prod 에 착수한다** — 아래 [환경 순서](#환경-순서--dev-를-완주한-뒤-prod-에-착수한다) |
| **선행 조건** | 앱 측 **5건** (2026-09-01 회신에서 4 → 5). **이것이 차단 조건이다** — [§0단계](#0단계--헬스체크드레이닝-정렬-본체보다-먼저-끝낸다) · 요청서 [`handoff/rolling-deploy-prerequisites.md`](../handoff/rolling-deploy-prerequisites.md) |
| **되돌리기** | **리스너 규칙 되돌리기** |

> ⚠️ `deployment_controller`는 변경 시 **리소스 재생성을 강제**한다. 그냥 apply하면 서비스가 destroy → create되어 태스크가 0이 되는 구간이 생긴다. 아래 절차는 그것을 피하기 위한 것이다.

---

## 절차

**현재 `api_desired_count = 1`인 상태에서 수행한다.** desired 를 올리지 않는다 —
증설은 노드가 2대가 되는 [Phase 7](./phase-07-dev-cache-asg.md)(dev) · [Phase 9](./phase-09-prod-asg.md)(prod) 의 작업이다.

### 환경 순서 — Dev 를 완주한 뒤 Prod 에 착수한다

**아래 [단계](#단계) 1~8 은 환경마다 한 번씩 수행하며, Dev 를 끝까지(6-b 포함) 마친 뒤에 Prod 를 시작한다.**

두 서비스는 정의가 사실상 동일하다 — `modules/services/{development,production}/api-service/main.tf`
양쪽 다 `deployment_controller { type = "CODE_DEPLOY" }` · `desired_count = 1` · t3.medium 노드 · ENI 2슬롯이다.
따라서 Dev 에서 밟은 절차가 Prod 에 그대로 옮겨간다.

**왜 Dev 가 먼저인가**

1. **이 Phase 가 테스트 리스너(9443)를 없애고, 그 상실을 갈음하는 것이 Dev promote 게이트다**(계획서 §3-5).
   그 게이트를 만드는 작업 자체를 Prod 에서 먼저 하는 것은 앞뒤가 맞지 않는다
2. **[Phase 5](./phase-05-dev-rds.md) 가 그 전제를 완성했다** — dev DB 가 RDS 8.4.11 이 되어 prod 와 엔진이 같아졌다
3. **이 Phase 시점에는 dev 와 prod 의 배포 비율이 같다** — 둘 다 임시 `100 / 200` 을 쓴다.
   갈라지는 것은 [Phase 7](./phase-07-dev-cache-asg.md)(dev `50 / 100`)부터이므로, **지금의 dev 는 prod 의 rolling 동작을 거의 그대로 재현한다.**
   계획서 §2.6 의 "Dev 는 surge 배치를 검증하지 못한다"는 표는 **To-Be 정상상태(dev `50/100`) 기준**이며 이 구간에는 해당하지 않는다
4. 가장 위험한 단계인 **리스너 스왑**도 dev 는 같은 ALB 의 별도 규칙이라 절차가 그대로 리허설된다

**Dev 가 증명해 주지 못하는 것 — 이것만은 Prod 관찰 기간에서 본다**

| 항목 | Dev 로 검증되나 |
|---|---|
| rolling 시퀀스 · 슬롯 배치 | ✅ |
| readiness 분리 동작 (기동 직후 트래픽 유입 방지) | ✅ |
| 서킷 브레이커 자동 롤백 | ✅ |
| 리스너 스왑 절차 | ✅ |
| **in-flight 요청 절단 여부** (드레이닝 값 정렬) | ❌ **실트래픽이 없으면 드러나지 않는다** |
| 구·신 버전이 동시에 실트래픽을 받는 구간 | ❌ 같은 이유 |

→ 드레이닝 값(dereg / Spring graceful / `stopTimeout`)이 실제로 맞는지는 **부하가 있어야 드러난다.**
Dev 에서 보려면 스왑·배포 시점에 합성 부하를 걸어야 하고, 그렇지 않다면 **Prod 관찰 기간이 이 값의 유일한 검증 창**이다.
검증 항목에 그에 맞는 지표를 명시해 두었다.

### ⚠️ desired = 1 구간에는 계획서의 To-Be 비율을 쓸 수 없다

ECS 는 두 값을 desired 에 곱한 뒤 **서로 다른 방향으로 정수화**한다 —
`minimumHealthyPercent` 는 **올림**, `maximumPercent` 는 **내림**이다.

| 설정 | 최소 유지 | 상한 | desired = 1 에서 |
|---|---|---|---|
| Prod To-Be `100 / 150` | ceil(1.0) = **1** | floor(1.5) = **1** | 상한이 1인데 1개를 내릴 수도 없다 → **배포 교착** |
| Dev To-Be `50 / 100` | ceil(0.5) = **1** | floor(1.0) = **1** | 동일 → **배포 교착** |
| **임시 `100 / 200`** | **1** | floor(2.0) = **2** | 신 1개 기동 → 구 1개 제거 ✅ |

계획서 §2.1 의 `100/150` · `50/100` 은 **desired 2 · 4슬롯 플릿을 전제로 계산된 값**이다.
그대로 쓰면 `update-service` 가 신규 태스크를 하나도 띄우지 못하고 배포가 멈춘다.

→ **이 Phase 에서는 임시로 `100 / 200` 을 쓰고, desired 를 2로 올릴 때 To-Be 값으로 바꾼다**
— dev 는 [Phase 7](./phase-07-dev-cache-asg.md) 에서 `50 / 100`, prod 는 [Phase 9](./phase-09-prod-asg.md) 에서 `100 / 150`.
`deployment_minimum_healthy_percent` / `deployment_maximum_percent` 는 `deployment_controller` 와 달리
**in-place 변경**이라 서비스 재생성을 유발하지 않는다. 미루어도 안전하다.

### 슬롯 회계 (노드 1대 = t3.medium, ENI 2슬롯)

**dev·prod 노드가 같은 타입이고 각각 API 태스크 1개만 awsvpc 로 뜨므로 회계가 동일하다.**
(Redis 는 host 모드라 ENI 를 쓰지 않는다. dev 의 MySQL 컨테이너는 [Phase 5](./phase-05-dev-rds.md) 에서 사라졌다.)

| 구간 | 슬롯 | 비고 |
|---|---|---|
| 1~5 (구·신 병존) | 구 1 + 신 1 = **2/2** | **여유 0. 이 구간에는 양쪽 다 배포할 수 없다** — 짧게 유지할 것 |
| 6-a 이후 (구 desired 0) | 신 1 = **1/2** | 배포 피크(임시 200%) 2태스크가 여기 들어간다 |

배포 피크 2태스크의 메모리는 1,370×2 + Redis 128 + ECS 오버헤드 ~500 ≈ **3.37 GiB** 로
t3.medium 가용치(~3.75 GiB) 안이다. 배치 판단은 `memoryReservation = 500` 기준이라 막히지 않는다.

### 0단계 — 헬스체크·드레이닝 정렬 (본체보다 먼저 끝낸다)

**[요청서 §4·§5](../handoff/rolling-deploy-prerequisites.md) 에서 확정된 값과 순서다. 이것이 끝나야 아래 [단계](#단계) 1번에 들어간다.**

#### 확정된 드레이닝 값

| 값 | 주체 | 현재 | 확정 | 근거 |
|---|---|---|---|---|
| ALB `deregistration_delay` | 인프라 | **미설정 = 300초** | **60초** | 결제 승인 상한 30초(Payple 왕복 2회 × read 10초 + connect 5초)를 덮어야 한다 |
| Spring `timeout-per-shutdown-phase` | 앱 | **이미 20초** | 20초 유지 | 요청서의 "확인 필요"는 틀렸다 — 처음부터 적용돼 있었다 |
| ECS `stopTimeout` | 인프라 | **태스크 정의에 없음** (노드 `user_data` 30초) | **90초** | graceful 20초 **뒤에** executor 종료 대기가 붙는다 |
| `mail`·`webhook` executor `awaitTermination` | 앱 | 30초 | **20초** | 20+20+20 = 60초 ≤ stopTimeout 90 |

> ⚠️ **`stopTimeout` 은 노드가 아니라 태스크 정의에 넣는다.** 지금 값은
> `prod_user_data.sh:25` 의 `ECS_CONTAINER_STOP_TIMEOUT=30s` 이고(dev 는 그 줄이 아예 없어
> 에이전트 기본값 30초), **`user_data` 는 고쳐도 실행 중 노드에 반영되지 않는다.**
> 태스크 정의 필드로 넣으면 노드 교체가 필요 없고, 모듈이 환경별이라 dev 먼저가 가능하다.
> 태스크 정의 값이 에이전트 설정을 이기는지는 **dev 에서 실측 확인**한다.

> ⚠️ **`dereg 300 → 60` 은 in-flight 보호를 줄이는 방향이다.** 지금 살아남는 60MB 업로드(~96초)가
> 앞으로는 잘린다(60+20 = 80초). **백엔드가 의도적으로 수용하겠다고 명시**했다
> ([§4-4](../handoff/rolling-deploy-prerequisites.md)). 근본 해법인 presigned 직행은 별건이다.

> 태스크 1개 교체가 **최악 120초**(dereg 60 + 종료 60)가 된다. desired 2 가 되는
> [Phase 7](./phase-07-dev-cache-asg.md)(dev)·[9](./phase-09-prod-asg.md)(prod) 에서는 배포 1회가 **최악 4분대**다.

#### ⛔ 선행 리팩터 — 타깃그룹 변수를 환경별로 쪼갠다

**타깃그룹 4개(prod·dev 의 blue/green)가 `var.health_check_path` 하나를 공유한다**
(`modules/infrastructure/load-balancer/main.tf` 의 39·67·99·127행. 값은
`environments/shared/main.tf:62` 한 곳에서만 들어간다).

→ **경로를 dev 만 readiness 로 바꿀 수 없다.** 바꾸는 순간 prod 타깃그룹도 함께 바뀌고,
prod 앱에 그 엔드포인트가 없으면 **60초 뒤 prod 전 태스크가 unhealthy** 가 된다
(prod TG 는 `unhealthy_threshold 2 × interval 30`).

`deregistration_delay` 도 4개 전부 미설정이라 같은 문제가 있다. **둘을 함께 쪼갠다:**

| | 지금 | 리팩터 직후 |
|---|---|---|
| prod TG | `var.health_check_path` = `/actuator/health` | `var.prod_health_check_path` = `/actuator/health` |
| dev TG | `var.health_check_path` = `/actuator/health` | `var.dev_health_check_path` = `/actuator/health` |

**값이 불변이므로 `terraform plan` 은 No changes 여야 한다 — 그것이 prod 무영향의 증거다.**

⚠️ `environments/{prod,dev}/variables.tf` 의 `health_check_path` 는 **어느 모듈에도 연결되지 않은
죽은 변수다.** 고치고 apply 해도 plan 에 아무것도 뜨지 않는다. 여기를 고치지 말 것.

#### 순서 — **항상 앱이 먼저다**

인프라가 먼저 나가면 ALB 가 없는 경로를 보게 되어 장애가 된다. 앱이 먼저 나가면
엔드포인트가 생기기만 하고 아무도 보지 않으므로 무해하다. **동시 배포 조율은 필요 없다.**

| 순서 | 주체 | 작업 |
|---|---|---|
| 1 | 인프라 | 타깃그룹 변수 분리 + WAF `STARTS_WITH "/actuator/health"` — **값 불변** |
| 2 | 앱 | PR① **dev 배포** (readiness/liveness · `mail` off · executor 20s) |
| 3 | 앱 | 로컬 SIGTERM 실측 → 총 종료 시간 공유 |
| 4 | 인프라 | **dev 만** 경로 → readiness · `healthCheck` → liveness · `stopTimeout 90` · dereg 60 |
| 5 | 공동 | dev 검증 — 기동 직후 `OUT_OF_SERVICE` → `UP` 전이 |
| 6 | 앱 | PR① **prod 배포** |
| 7 | 인프라 | prod 동일 적용 |
| 8 | 앱 | **스케줄러 23개 다중 실행 전수 점검** ← 5번째 차단 조건, 가장 오래 걸린다 |

> ⚠️ **`management.health.mail.enabled: false` 만은 위 순서를 기다리지 않는다.**
> `MailHealthIndicator` 가 `/actuator/health` 호출마다 SMTP 에 실제 접속하고 있고,
> **prod 는 SMTP 가 흔들리면 60초 만에 타깃에서 빠진다.** 롤링과 무관하게 지금 열려 있는 위험이다.

### 사전 확인 — `spring_app_image` 를 실행 중 이미지와 맞춘다

**신 rolling 서비스는 Terraform 이 만든 태스크 정의로 뜬다.** 기존 서비스는 CodeDeploy 가
태스크 정의를 소유(`ignore_changes = [task_definition]`)하므로 tfvars 의 값이 실제 배포본과
어긋나 있을 수 있다 — [Phase 5](./phase-05-dev-rds.md) 에서 확인된 함정이다.

**낡은 태그로 신 서비스를 띄우면 리스너 스왑이 곧 "구버전으로의 롤백 사고"가 된다.**

착수 직전에 환경별로 확인한다:

```bash
# 실제 실행 중인 이미지
aws ecs describe-services --profile groble-terraform --cluster groble-cluster \
  --services groble-<env>-service \
  --query 'services[0].taskDefinition' --output text \
| xargs -I{} aws ecs describe-task-definition --profile groble-terraform --task-definition {} \
  --query 'taskDefinition.containerDefinitions[0].image' --output text
```

이 값과 `environments/<env>/terraform.tfvars` 의 `spring_app_image` 가 **정확히 같아야** 다음으로 넘어간다.

### 단계

**아래 1~8 을 Dev 에서 완주한 뒤, 같은 순서로 Prod 에서 수행한다.**

1. **신 서비스 생성** — 기존 **Green 타깃그룹**에 rolling 방식 ECS 서비스 추가
   ```hcl
   deployment_controller { type = "ECS" }
   deployment_minimum_healthy_percent = 100
   deployment_maximum_percent         = 200   # 임시값 — Phase 7 에서 dev 100 / Phase 9 에서 prod 150 으로
   deployment_circuit_breaker { enable = true, rollback = true }
   ```
   - 기존(CodeDeploy) 서비스는 **그대로 살려둔다**
2. 신 서비스의 태스크가 Green TG에서 **healthy**가 될 때까지 대기
3. **테스트 리스너(9443)로 신 서비스를 먼저 검증** — 이 리스너는 아직 존재하므로 마지막으로 활용한다
4. **ALB 리스너(443) 규칙을 Blue TG → Green TG로 스왑**
5. **관찰 기간** (최소 30분): 5xx, p99, 에러율 지표 확인
6. **`6-a` 와 `6-b` 를 반드시 나눠서 진행한다** (아래 참조)
   - **6-a.** 이상 없으면 구 서비스 **`desired_count = 0`** — 리소스는 남긴다
     → 슬롯이 1개 풀린다. **여기서 검증 항목의 rolling 배포 · 서킷 브레이커 확인을 수행한다**
   - **6-b.** 검증이 끝나면 구 서비스 **리소스 제거** ← *되돌릴 수 없어지는 지점*
7. CodeDeploy 애플리케이션·배포그룹·IAM 역할 제거 (Phase 12에서 일괄 정리해도 무방)
   - **dev·prod 가 CodeDeploy 애플리케이션을 공유하므로, 실제 제거는 Prod 까지 끝난 뒤에 한다**
8. **CI 파이프라인 전환**: `appspec` 기반 CodeDeploy 호출 → 태스크 정의 등록 + `aws ecs update-service`
   - Terraform은 `lifecycle { ignore_changes = [task_definition] }` 유지

> **6번을 왜 쪼개는가.** 검증 항목은 "구 서비스 제거 **전에** rolling 배포 1회 성공"을 요구하는데,
> 구 서비스가 태스크를 들고 있는 동안에는 슬롯이 2/2로 꽉 차 **surge 배포 자체가 불가능**하다.
> 구 서비스를 `desired 0` 으로 내려 슬롯을 비우면 검증이 가능해지고, 리소스는 남아 있으므로
> 롤백 경로도 유지된다 — 다만 **초 단위에서 몇 분으로 열화**된다(아래 롤백 절 참조).

## 검증

### 착수 전 (환경별)

- [ ] `spring_app_image` 가 실행 중 이미지와 일치하는지 — [사전 확인](#사전-확인--spring_app_image-를-실행-중-이미지와-맞춘다)
- [ ] `terraform plan` 에 **기존 서비스의 replace 가 없는지** 육안 확인

### Dev 에서 (전량 수행 — Prod 착수 조건)

- [ ] 리스너 스왑 후 트래픽이 신 서비스 태스크로 가는지 (TG별 `RequestCount`)
- [ ] CI에서 **rolling 배포를 1회 실제로 수행**해 정상 동작 확인 — **6-a 이후에 한다** (그 전에는 슬롯이 없다)
- [ ] 서킷 브레이커가 동작하는지 — **의도적으로 실패하는 이미지를 배포해 롤백 확인**
- [ ] readiness 분리가 실제로 트래픽 유입을 막는지 — 기동 직후 TG 상태가 `initial → unhealthy → healthy` 를 거치는지
- [ ] `min/max` 가 **임시값 `100/200`** 인지, [Phase 7](./phase-07-dev-cache-asg.md) 에서 `50/100` 으로 되돌릴 항목으로 인계되었는지

### Prod 에서

- [ ] 위 Dev 항목 전부 재수행
- [ ] `min/max` 임시값 `100/200` → [Phase 9](./phase-09-prod-asg.md) 에서 `100/150` 으로 되돌릴 항목으로 인계되었는지
- [ ] **드레이닝 파라미터가 [0단계](#0단계--헬스체크드레이닝-정렬-본체보다-먼저-끝낸다) 확정값으로 적용됐는지** — dereg 60 / graceful 20 / `stopTimeout` 90
- [ ] **드레이닝이 실제로 요청을 자르지 않는지** — 스왑 직후와 rolling 배포 중 아래 지표가 **평상시 대비 증가하지 않아야 한다.**
  Dev 로는 검증되지 않는 항목이므로 여기서 본다 (합성 부하를 걸면 Dev 에서도 가능)

  | 지표 | 무엇을 잡나 |
  |---|---|
  | `TargetConnectionErrorCount` | ALB 가 태스크에 연결하지 못함 = 드레이닝 끝나기 전에 죽었다 |
  | `HTTPCode_ELB_502_Count` | 백엔드가 응답 중 끊김 |
  | `HTTPCode_ELB_504_Count` | in-flight 요청이 timeout — graceful 이 부족 |
  | `HTTPCode_Target_5XX_Count` | 앱이 반환한 5xx (구·신 버전 공존 문제 후보) |
  | p99 `TargetResponseTime` | 평상시 0.24~0.42초 (계획서 §2.1 기준선) |

## 롤백

**리스너 규칙을 Blue TG로 되돌린다.** 구 서비스가 그대로 살아 있으므로 즉시 복구된다.
이 마이그레이션에서 가장 깔끔한 되돌리기 지점이다.

**단, 6-a 를 지나면 롤백 품질이 한 단계 떨어진다.**

| 시점 | 롤백 방법 | 소요 |
|---|---|---|
| 1~5 (구 서비스 desired 1) | 리스너 규칙만 되돌린다 | **초 단위** |
| 6-a 이후 (구 서비스 desired 0) | 구 서비스 `desired 1` 복구 → healthy 대기 → 리스너 되돌리기 | **몇 분** |
| 6-b 이후 (구 서비스 제거) | ❌ 없다 | — |

> 되돌릴 수 없게 되는 시점: **6-b, 구 CodeDeploy 서비스 리소스 제거**.
> 그 전에 rolling 배포 1회 이상 성공과 서킷 브레이커 동작을 확인한다(6-a 구간에서 수행).

**Dev 를 먼저 완주하는 것이 Prod 롤백의 사전 보험이다** — Prod 에서 6-b 로 넘어갈 때
"이 절차가 이 코드에서 동작한다"가 이미 dev 에서 실증되어 있다.

---

[← Phase 4 — 모니터링 노드 재구축](./phase-04-monitoring-node-rebuild.md) · [이관 절차 목차](README.md) · [다음: Phase 7 — Dev ElastiCache + ASG 전환 →](./phase-07-dev-cache-asg.md)
