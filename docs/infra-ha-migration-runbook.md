# 인프라 이관 실행 절차 (Migration Runbook)

> [`infra-ha-improvement-plan.md`](./infra-ha-improvement-plan.md)에서 확정한 To-Be 구조로
> **현재 운영 중인 인프라를 안전하게 옮기는 순서와 절차.**
>
> 설계의 "무엇을·왜"는 계획서에, 실행의 "어떤 순서로·어떻게 되돌리는가"는 이 문서에 있다.

---

## 이 문서의 원칙

1. **한 번에 한 가지만 바꾼다.** 문제가 생겼을 때 원인이 명확해야 한다.
2. **모든 단계에 되돌리기 지점이 있다.** 되돌릴 수 없는 단계는 그 사실을 명시하고, 사전 검증을 더 무겁게 한다.
3. **사용자 영향이 없는 단계를 앞에 둔다.** 위험한 단계에 도달했을 때는 이미 안전망(알람·관측·state 백업)이 갖춰져 있어야 한다.
4. **각 단계는 독립적으로 중단 가능하다.** 도중에 멈춰도 인프라가 일관된 상태로 남아야 한다.

---

## 전체 순서 요약

| Phase | 내용 | 사용자 영향 | 되돌리기 |
|---|---|---|---|
| **0** | Terraform state → S3 backend + 잠금 | 없음 | 로컬 state 복원 |
| **1** | CloudWatch 알람 백스톱 + SNS 외부 알림 | 없음 | 리소스 삭제 |
| **2** | Prometheus `ec2_sd` 전환 + Grafana as-code | 없음 | 이전 이미지 태그로 롤백 |
| **3** | NAT Gateway + S3 Gateway Endpoint, 라우트 전환 | 짧은 egress 블립 | 라우트 되돌리기 |
| **4** | 배포 컨트롤러 CodeDeploy → ECS rolling | 없음 (리스너 스왑) | **리스너 규칙 되돌리기** |
| **5** | 모니터링 노드 재구축 (private 2c, AL2023) + OTLP DNS 간접화 | 없음 (구 노드 병존) | DNS 레코드 되돌리기 (재배포 없음) |
| **6** | Prod Redis → ElastiCache (**stop-first**, rolling 아님) | **진행 중 결제 세션 소실 + 1~2분 순단** ⚠️ | 되돌려도 재소실 |
| **7** | Prod ASG 전환 (구 노드 드레인) | 없음 | 구 노드 재활성화 |
| **8** | Dev 전환 (RDS + ElastiCache + ASG) | Dev만 | 단계별 |
| **9** | 접근 경로 정리 (WireGuard/bastion/22 폐기) | 없음 | SG 규칙 복원 |
| **10** | Secrets → SSM Parameter Store | 없음 (rolling 재배포) | 이전 태스크 정의 |
| **11** | 잔재 정리 및 문서 갱신 | 없음 | — |

**Phase 6 이전까지는 사용자 영향이 사실상 0이다.** 그 지점까지 최대한 검증을 쌓고 진입한다.

---

## 착수 전 체크리스트

- [ ] `terraform version` ≥ 1.10 (Phase 0의 S3 네이티브 잠금 요건)
- [ ] `aws sts get-caller-identity --profile groble-terraform` 정상 (SSO 토큰 유효)
- [ ] 현재 state 파일 4개를 **작업 외부(로컬 백업 디렉터리)에 복사해 둔다**
- [ ] `terraform plan`이 모든 환경에서 **no changes**로 깨끗한지 확인 — drift가 있으면 먼저 해소
- [ ] 계획서 §3 "rolling 전환의 차단 조건 — 앱 측 작업" **4건**(expand/contract 합의 · readiness/liveness 분리 · graceful shutdown · 드레이닝 값 정렬)이 groble-backend에서 완료되었는지 — **Phase 4의 차단 조건**. Phase 0~3은 이와 무관하게 먼저 진행할 수 있다
- [ ] **WireGuard 51820 소스를 `0.0.0.0/0` → 팀 IP로 축소** (계획서 §2.5 선행 즉시 조치 — Phase 9까지 6~8주를 열어둘 이유가 없다)
- [ ] 저트래픽 시간대 확인 (Phase 3·6에 필요)
- [ ] 롤백 판단자와 연락 체계 합의

### 중단(Abort) 기준

아래 중 하나라도 해당하면 **즉시 해당 Phase를 롤백하고 원인 분석 후 재개**한다.

- ALB 5xx가 기준선 대비 유의미하게 상승
- 타깃그룹 `UnHealthyHostCount` > 0이 5분 이상 지속
- ECS 서비스가 desired count를 10분 이상 충족하지 못함
- Terraform apply가 예상하지 못한 리소스 **삭제/재생성**을 계획에 포함 (plan을 반드시 육안 확인)

---

## Phase 0 — Terraform state를 S3로 이전

**목적**: 이후 모든 단계가 state를 크게 조작한다. 잠금·이력·백업 없이 진행하지 않는다.
**사용자 영향**: 없음 (실물 인프라 무변경)

### 절차

1. state 저장용 S3 버킷 생성 — **시크릿 저장소로 취급한다** (Phase 10 전까지 평문 비밀번호가 담긴 state가 여기 올라간다, 계획서 §2.7)
   - versioning ON, SSE-KMS 암호화 (키 정책도 Terraform 실행 주체로 한정)
   - Block Public Access 4항목 전부 ON
   - 버킷 정책: `aws:PrincipalArn`으로 Terraform 실행 role/SSO 권한 세트만 허용, 그 외 `Deny`
   - CloudTrail S3 데이터 이벤트로 read 기록
2. 각 환경의 backend 블록 작성 — `shared` / `prod` / `dev` / `monitoring` 4곳

```hcl
terraform {
  backend "s3" {
    bucket       = "groble-terraform-state"
    key          = "environments/<env>/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

3. 환경별로 `terraform init -migrate-state` 실행
4. `data "terraform_remote_state"`의 `backend = "local"`을 S3로 변경 — **3곳** (`prod`, `dev`, `monitoring`의 `main.tf`)

### 검증
- [ ] 각 환경에서 `terraform plan` → **no changes**
- [ ] 다른 터미널에서 동시에 `terraform plan` 실행 시 **잠금이 걸리는지** 확인
- [ ] S3 버킷에 state 객체 4개와 버전이 생성되었는지
- [ ] Terraform 실행 주체가 아닌 자격증명(예: 읽기 전용 role)으로 `aws s3 cp`가 **거부되는지**

### 롤백
backend 블록을 제거하고 백업해 둔 로컬 state를 복원한 뒤 `terraform init -migrate-state`.

---

## Phase 1 — 알람 백스톱 확보

**목적**: 이후 단계에서 문제가 생겼을 때 **자체 호스팅 관측이 죽어도 알림이 도달**해야 한다. Phase 4의 서킷 브레이커도 이 알람에 의존한다.
**사용자 영향**: 없음

### 절차

1. SNS 토픽 생성 + 외부 채널 구독 (Slack webhook / 이메일)
2. CloudWatch 알람 생성 — 최소 세트:
   - ALB `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`
   - TargetGroup `UnHealthyHostCount` (Prod Blue/Green TG)
   - ALB `TargetResponseTime` p99
   - RDS `CPUUtilization`, `DatabaseConnections`, `FreeStorageSpace`
3. 임계치는 **현재 기준선을 1주일 관측한 뒤** 확정 (초기에는 넉넉하게)
4. **같은 1주 동안 트래픽 기준선을 함께 기록한다** (계획서 §4 To-Do 9) — 알람 임계치와 별개로, 용량 결정의 근거 데이터가 지금 없다:
   - ALB `RequestCountPerTarget`(합계·피크), `TargetResponseTime` p50/p99
   - 피크 시간대와 **피크/평균 비율**
   - Prod API 태스크 CPU/메모리 사용률 (cAdvisor)
   - 결과를 계획서 §2.1 옆에 표로 남긴다. desired 2가 충분한지, 동적 스케일링(향후 개선 Low-3) 트리거에 얼마나 가까운지가 이 표로 판단된다

### 검증
- [ ] 알람을 수동으로 `ALARM` 상태로 전환해 **외부 채널까지 실제로 도달**하는지 확인
- [ ] 알람이 `INSUFFICIENT_DATA`로 방치되지 않는지
- [ ] 트래픽 기준선 표가 작성되었는지

### 롤백
리소스 삭제. 다른 단계에 영향 없음.

---

## Phase 2 — 관측 선행 전환 (ASG보다 반드시 먼저)

**목적**: ASG 도입 후 새 노드가 **관측 사각지대에 들어가는 것을 막는다.** 순서가 뒤바뀌면 노드가 조용히 사라지고, 하필 그 시점이 마이그레이션 중이라 가장 위험하다.
**사용자 영향**: 없음

### 2-1. Prometheus `ec2_sd_config` 전환

1. Prometheus Task Role에 `ec2:DescribeInstances` 인라인 정책 추가 (**현재 없음**)
2. **기존 3개 `aws_instance`에 `Cluster=groble-cluster`, `environment`, `Type` 태그가 붙어 있는지 확인**하고 없으면 추가 — `ec2_sd`는 인스턴스 태그를 본다. (Phase 7의 ASG는 태그 전파 설정으로 같은 키를 붙인다)
3. `groble-images` 저장소의 Prometheus config를 `static_configs` → `ec2_sd_config`로 변경
   - 태그 필터: `Cluster = groble-cluster`
   - relabel: EC2 태그 `environment`, `Type`을 라벨로 승격
   - 포트별 잡 분리: node-exporter(9100), cAdvisor(8081)
4. CI에서 `promtool check config` 게이트 추가
5. **"기대 타깃 수 미달" 알람의 기대값을 상수로 박지 않는다** — config baking 시 환경별 노드 수 변수에서 주입하거나, 최소한 "ASG desired 변경 시 함께 바꿀 것" 목록에 등재 (계획서 §2.4)
6. 새 이미지 태그로 Prometheus 서비스 배포

### 2-2. Grafana 프로비저닝 as-code

1. 현재 Grafana UI에서 **대시보드·데이터소스·알림 규칙을 JSON으로 export**
2. `groble-images`에 provisioning 구조로 정리 (`/etc/grafana/provisioning/{datasources,dashboards,alerting}`)
3. provisioned 대시보드는 **읽기 전용**으로 설정 (UI 편집분과 코드가 갈라지지 않게)
4. 새 이미지로 Grafana 서비스 배포

### 검증
- [ ] Prometheus `/targets`에서 **기존 노드 3대가 모두 UP**으로 잡히는지 (전환 전과 동일한 타깃 수)
- [ ] Grafana 대시보드가 프로비저닝으로 복원되었는지, 기존 패널이 정상 렌더되는지
- [ ] `up == 0` 알람과 **"기대 타깃 수 미달" 알람** 동작 확인

### 롤백
이전 이미지 태그로 서비스 되돌리기. IAM 정책은 남겨둬도 무해하다.

> ⚠️ **이 Phase를 건너뛰고 Phase 7로 가지 않는다.** 새 ASG 노드가 스크레이프되지 않는 상태로 마이그레이션을 진행하면, 문제가 생겨도 지표가 없다.

---

## Phase 3 — NAT Gateway 전환

**목적**: 모니터링 노드의 NAT 겸직을 제거한다. 되돌리기가 쉬워 초기에 배치했다.
**사용자 영향**: 라우트 교체 순간 **기존 연결이 끊긴다**(짧음). ECR pull 중이면 배포가 실패할 수 있다.
**시점**: 저트래픽 시간대, **배포가 없는 시간대**

### 절차

1. NAT Gateway 생성 — **2c public subnet** (`10.0.2.0/24`), EIP 할당
2. **S3 Gateway Endpoint 생성** (무료) — private route table에 연결
3. private route table의 `0.0.0.0/0`을 **NAT 인스턴스 ENI → NAT Gateway**로 변경
   - Terraform: `aws_route.private_nat_route`의 `network_interface_id` → `nat_gateway_id`
4. 모니터링 노드의 `source_dest_check`와 iptables MASQUERADE는 **아직 건드리지 않는다** (롤백 여지 유지)

### 검증
- [ ] private 노드에서 외부 도달 확인: `curl -I https://api.ecr.ap-northeast-2.amazonaws.com`
- [ ] ECR pull 정상 동작 (테스트 배포 1회)
- [ ] SSM/S3 접근 정상
- [ ] NAT Gateway CloudWatch 지표에 트래픽이 잡히는지

### 롤백
라우트를 NAT 인스턴스 ENI로 되돌린다. 모니터링 노드의 NAT 설정을 그대로 두었으므로 즉시 복구된다.

---

## Phase 4 — 배포 컨트롤러 전환 (CodeDeploy → ECS rolling)

**목적**: Blue/Green은 4슬롯 플릿에서 여유가 0이라 유지할 수 없다(계획서 §2.6).
**사용자 영향**: 없음 — 신 서비스가 준비된 뒤 리스너를 스왑한다.
**선행 조건**: 계획서 §4 To-Do 1번(expand/contract 팀 합의) 완료. **이것이 차단 조건이다.**

> ⚠️ `deployment_controller`는 변경 시 **리소스 재생성을 강제**한다. 그냥 apply하면 서비스가 destroy → create되어 태스크가 0이 되는 구간이 생긴다. 아래 절차는 그것을 피하기 위한 것이다.

### 절차

**현재 `api_desired_count = 1`인 상태에서 수행한다** (슬롯 2개만 사용 → 여유 확보).

1. **신 서비스 생성** — 기존 **Green 타깃그룹**에 rolling 방식 ECS 서비스 추가
   ```hcl
   deployment_controller { type = "ECS" }
   deployment_minimum_healthy_percent = 100
   deployment_maximum_percent         = 150
   deployment_circuit_breaker { enable = true, rollback = true }
   ```
   - 기존(CodeDeploy) 서비스는 **그대로 살려둔다**
2. 신 서비스의 태스크가 Green TG에서 **healthy**가 될 때까지 대기
3. **테스트 리스너(9443)로 신 서비스를 먼저 검증** — 이 리스너는 아직 존재하므로 마지막으로 활용한다
4. **ALB 리스너(443) 규칙을 Blue TG → Green TG로 스왑**
5. **관찰 기간** (최소 30분): 5xx, p99, 에러율 지표 확인
6. 이상 없으면 구 서비스 `desired_count = 0` → 리소스 제거
7. CodeDeploy 애플리케이션·배포그룹·IAM 역할 제거 (Phase 11에서 일괄 정리해도 무방)
8. **CI 파이프라인 전환**: `appspec` 기반 CodeDeploy 호출 → 태스크 정의 등록 + `aws ecs update-service`
   - Terraform은 `lifecycle { ignore_changes = [task_definition] }` 유지

### 검증
- [ ] 리스너 스왑 후 트래픽이 신 서비스 태스크로 가는지 (TG별 `RequestCount`)
- [ ] CI에서 **rolling 배포를 1회 실제로 수행**해 정상 동작 확인
- [ ] 서킷 브레이커가 동작하는지 — 의도적으로 실패하는 이미지를 Dev에 배포해 롤백 확인
- [ ] 드레이닝 파라미터 정렬 (계획서 §3-3): `deregistration_delay` / `stopTimeout` / Spring graceful 값 확정 및 적용

### 롤백
**리스너 규칙을 Blue TG로 되돌린다.** 구 서비스가 그대로 살아 있으므로 즉시 복구된다.
이 마이그레이션에서 가장 깔끔한 되돌리기 지점이다.

---

## Phase 5 — 모니터링 노드 재구축

**목적**: 현재 모니터링 노드는 public 2a에 있고 NAT·bastion·VPN을 겸직한다. private 2c의 AL2023 노드로 옮긴다.
**사용자 영향**: 없음 — 구 노드를 병존시킨 채 전환한다.

> 모니터링 노드는 계획서 §0에 따라 **pet으로 유지**한다. ASG로 만들지 않는다.

### 절차

1. **신 모니터링 노드 생성** — `t3.small`, ECS-optimized AL2023, **private 2c**, public IP 없음, 고정 사설 IP
   - user_data: `/etc/ecs/ecs.config`에 클러스터명 + `ECS_INSTANCE_ATTRIBUTES={"environment":"monitoring"}`
   - 인스턴스 프로파일에 `AmazonSSMManagedInstanceCore` 포함
2. **SSM 접속 확인** — `aws ssm start-session --target <instance-id>` (구 노드 폐기의 선행 조건)
3. 모니터링 스택(Grafana/Prometheus/Loki/otelcol)을 신 노드로 배치
   - Grafana는 Phase 2의 provisioning으로 **자동 복원**된다
   - Loki 로그는 S3에 있으므로 보존된다
   - Prometheus 로컬 15일치는 **유실을 수용**한다
4. ALB 모니터링 타깃그룹을 신 노드로 재연결 → `monitor.groble.im` 접속 확인
5. **OTLP 엔드포인트를 DNS로 간접화한 뒤 전환** (계획서 §2.4)
   - 5-a. (신 노드 생성 **전에** 해도 된다) Route 53 private hosted zone `internal.groble.im` 생성 + VPC 연결, `otel.internal.groble.im` A 레코드를 **구 노드 IP**로 등록, TTL 60초
   - 5-b. 앱의 `OTEL_EXPORTER_OTLP_ENDPOINT`를 IP → `http://otel.internal.groble.im:4318`로 변경 → rolling 재배포 (Phase 4의 rolling을 실제로 활용). 이 시점엔 여전히 구 노드로 간다 — **동작 변화 없이 간접화만 도입**
   - 5-c. 사전 확인: JVM DNS 캐시 TTL이 유한한지 (계획서 §3-8, To-Do 12). 무기한이면 5-d가 재배포 없이는 반영되지 않는다
   - 5-d. 레코드 값을 **신 노드 IP로 변경** → 60초 내 트래픽이 신 노드로 이동. **앱 재배포 없음**
   - 이후 모니터링 노드를 다시 교체할 때는 5-d만 반복하면 된다
6. 구 모니터링 노드에서 모니터링 스택만 중지 — **NAT/bastion/WireGuard는 아직 살려둔다**

### 검증
- [ ] Grafana 대시보드가 신 노드에서 정상 (프로비저닝 복원 확인)
- [ ] Prometheus 타깃이 `ec2_sd`로 전부 잡히는지
- [ ] 5-b 후 앱 로그·트레이스가 **여전히 구 노드**로 들어오는지 (간접화 자체의 검증)
- [ ] 5-d 후 60초 내 앱 트레이스·로그가 **신 otelcol**로 들어오는지 (Loki에 신규 로그 유입 확인) — 재배포 없이 옮겨졌는지가 핵심
- [ ] SSM으로 신 노드 접속 가능

### 롤백
DNS 레코드를 구 노드 IP로 되돌린다 (재배포 없음). 구 노드의 스택을 재기동.

---

## Phase 6 — Prod Redis → ElastiCache ⚠️

**목적**: host-mode 싱글턴 컨테이너는 cattle 노드에서 유지할 수 없다. Phase 7(구 노드 드레인)의 **선행 조건**이다.
**사용자 영향**: **진행 중이던 체크아웃 세션·재고 예약·멱등성 키가 전부 소실된다.**
**시점**: **저트래픽 시간대 필수.** TTL이 30분이므로 최소 30분의 안정화 창을 확보한다.

> 이 Phase는 **되돌려도 손실이 반복된다**(되돌리는 순간 다시 상태가 바뀐다). 전후로 결제 지표를 주의 깊게 본다.

### 절차

1. **ElastiCache 생성** — `cache.t4g.micro`, **2c**, 단일 노드
   - Terraform 리소스는 **`aws_elasticache_replication_group`** (`num_cache_clusters = 1`, `automatic_failover_enabled = false`) — `aws_elasticache_cluster`가 아님. replica 추가가 온라인 변경이 되게 하기 위함 (계획서 §2.3)
   - 앱은 `primary_endpoint_address`를 바라본다
   - **유지보수 창을 트래픽 최저 시간대로 명시 지정** (기본값은 무작위)
   - **자동 스냅샷 활성화**
   - SG: API 태스크 SG로부터 6379 허용
2. 저트래픽 시간대 진입, **결제 지표 기준선 기록**
3. **stop-first 전환** — rolling이 아니다 ⚠️
   - 이유: surge rolling(`100/150`)으로 배포하면 구 태스크(컨테이너 Redis)와 신 태스크(ElastiCache)가 몇 분간 **동시에 실트래픽**을 받아 멱등성 키·재고 카운터가 두 저장소로 갈라진다(split-brain). 중복 결제 방어가 실제로 뚫리는 창이다 (계획서 §2.3).
   - 절차:
     ```bash
     # (a) 일시적으로 stop-first로 전환
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --deployment-configuration minimumHealthyPercent=0,maximumPercent=100
     # (b) REDIS_HOST를 ElastiCache 엔드포인트로 바꾼 태스크 정의로 배포
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --task-definition <new-revision>
     # (c) 신 태스크 healthy 확인 후 원래 값으로 복구
     aws ecs update-service --cluster groble-cluster --service groble-prod-service \
       --deployment-configuration minimumHealthyPercent=100,maximumPercent=150
     ```
   - 예상 순단: 구 태스크 종료 → 신 태스크 healthy까지 **1~2분** (JVM 기동 + 헬스체크). 저트래픽 창에서 수용한다.
   - Terraform 서비스 리소스에 `deployment_minimum_healthy_percent`가 선언되어 있으면 (c) 후 `terraform plan`이 no changes인지 확인한다.
4. **30분 안정화 관찰** — 결제 성공률, 5xx, 재고 관련 오류
5. 구 Redis ECS 서비스 제거

### 검증
- [ ] ElastiCache에 키가 쌓이는지 (`checkout:*`, `stock:reserved:*`, `user:cache:*`)
- [ ] 결제 플로우 E2E 1회 수동 확인
- [ ] 결제 성공률이 기준선 대비 유지되는지 (최소 1시간)
- [ ] 재고 예약/해제 정상 동작

### 롤백
`REDIS_HOST`를 구 컨테이너 IP로 되돌리고 **동일하게 stop-first로** 재배포. **다시 한 번 상태가 소실된다.**

### 남는 리스크
단일 노드이므로 **유지보수·장애 시 결제 상태 유실 창이 남는다.** replica 전환은 [`infra-future-improvements.md`](./infra-future-improvements.md)의 **Urgent #1**이다.

---

## Phase 7 — Prod ASG 전환

**목적**: 이 프로젝트의 본 목표. 무중단 하드웨어 교체가 가능한 구조로 전환한다.
**사용자 영향**: 없음 — 신 노드를 먼저 띄우고 구 노드를 드레인한다.
**선행 조건**: Phase 2(관측), Phase 6(Redis 외부화) 완료

### 절차

1. **Launch Template 작성**
   - AMI: SSM Parameter `/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id`
   - user_data: `/etc/ecs/ecs.config`에 `ECS_CLUSTER`, `ECS_INSTANCE_ATTRIBUTES={"environment":"production"}`, `ECS_RESERVED_MEMORY=512`, `ECS_CONTAINER_STOP_TIMEOUT`(§3-3에서 확정한 값)
   - 인스턴스 프로파일: 기존 ECS 인스턴스 롤 + `AmazonSSMManagedInstanceCore`
   - **키페어 지정하지 않음**
   - 루트 볼륨 30GB gp3, 암호화
2. **ASG 생성** — `desired = 2`, **2c 서브넷 고정**, mixed instances policy (`t3.medium` / `t3a.medium`)
   - instance refresh preferences: `min_healthy_percentage = 100`, `max_healthy_percentage = 200` (launch-before-terminate)
   - **태그 전파** — `ec2_sd`가 새 노드를 보려면 인스턴스에 태그가 붙어야 한다 (계획서 §2.4):
     ```hcl
     tag { key = "Cluster"     value = "groble-cluster" propagate_at_launch = true }
     tag { key = "environment" value = "production"     propagate_at_launch = true }
     tag { key = "Type"        value = "api"            propagate_at_launch = true }
     ```
     Launch Template `tag_specifications`와 **중복 정의하지 않는다** — 한 곳으로 통일
3. **Capacity Provider 생성 및 클러스터 연결**
   ```hcl
   managed_draining = "ENABLED"
   managed_scaling { status = "DISABLED" }   # 고정 크기 ASG
   ```
   - ⚠️ Phase 4에서 만든 신 서비스에 `capacity_provider_strategy`를 붙이는 변경은 **provider 버전에 따라 서비스 재생성을 강제할 수 있다** (계획서 §2.1). **plan에서 `aws_ecs_service`가 replace로 잡히면 apply하지 않는다.** launch type 서비스도 컨테이너 인스턴스 DRAINING으로 정상 드레인되므로, 이 경우 CP 전략 부착은 미루고 managed draining만으로 진행한다 (10번 리허설에서 실제 드레인 동작으로 확인)
4. **신 노드 검증** (구 노드와 병존 상태)
   - [ ] ECS 클러스터에 컨테이너 인스턴스로 등록되었는지
   - [ ] `environment=production` 속성이 붙었는지
   - [ ] EC2 콘솔/CLI에서 인스턴스에 `Cluster`·`environment`·`Type` 태그가 붙었는지 (`aws ec2 describe-instances --filters Name=tag:Cluster,Values=groble-cluster`)
   - [ ] Prometheus `/targets`에 **자동으로 나타나는지** (Phase 2의 `ec2_sd` 검증) — 위 태그가 없으면 여기서 조용히 빠진다
   - [ ] `aws ssm start-session`으로 접속되는지
   - [ ] credential 프록시 정상 — 태스크에서 AWS API 호출 성공 확인
5. **`memory_reservation`을 1000으로 변경** 후 태스크 재배포
6. **구 Prod 노드를 DRAINING으로 전환**
   ```bash
   aws ecs update-container-instances-state --cluster groble-cluster \
     --container-instances <old-instance-arn> --status DRAINING
   ```
7. 태스크가 신 노드로 이동 완료되는지 확인 (ALB healthy host 수 유지 확인)
8. 구 `aws_instance.prod_instance` 제거
9. **`api_desired_count`를 1 → 2로 증설**
10. **instance refresh 리허설** — 실제로 1회 수행해 무중단 교체가 동작하는지 확인 ⭐

### 검증
- [ ] **instance refresh 중 5xx가 0인지** — 이 프로젝트의 목표가 달성되었는지 확인하는 핵심 검증
- [ ] 드레이닝 시 in-flight 요청이 끊기지 않는지
- [ ] 노드 1대를 강제 종료했을 때 ASG가 자동 복구하는지, 태스크가 재배치되는지
- [ ] **복구 소요 시간 측정** — 종료 시각 → EC2 unhealthy 감지 → 신 인스턴스 기동 → ECS 등록 → 태스크 RUNNING 각 구간을 기록. 계획서 §2.1의 "실측 전 추정 3~5분+"를 이 값으로 갱신 (To-Do 10). 감지 구간이 길면 ASG 헬스체크 유예/EC2 상태 검사 설정을 조정할 근거가 된다
- [ ] launch type 서비스의 태스크가 DRAINING으로 정상 이동하는지 (3번에서 CP 전략 부착을 미룬 경우 이것이 무중단 교체의 근거)

### 롤백
구 노드를 `ACTIVE`로 되돌리고 ASG `desired = 0`. 구 인스턴스를 제거하기 전(8번)까지는 완전히 되돌릴 수 있다.
**8번 이후는 되돌리기가 어려워진다** — 이 지점을 넘기 전에 4~7번 검증을 충분히 한다.

---

## Phase 8 — Dev 전환

**목적**: Dev를 Prod와 같은 형태로 만들어 §3-5의 promote 게이트가 실제로 의미를 갖게 한다.
**사용자 영향**: Dev만. 개발 작업이 없는 시간대 권장.

### 절차

1. **Dev RDS 생성** (`db.t4g.micro`, 2c, 단일 AZ, 자동 백업)
2. 현재 Dev MySQL 컨테이너에서 **데이터 덤프 → RDS 복원**
   ```bash
   mysqldump ... > dev.sql && mysql -h <rds-endpoint> < dev.sql
   ```
3. **Dev ElastiCache 생성** (`cache.t4g.micro`, 2c) — Prod와 동일하게 `aws_elasticache_replication_group` 리소스로 (모듈을 공유하면 자연히 그렇게 된다)
4. Dev 앱의 `DB_HOST` / `REDIS_HOST` 변경 → 재배포
5. 구 Dev MySQL·Redis 컨테이너 서비스 제거
6. **Dev ASG 전환** — Phase 7과 동일한 절차 (Launch Template, ASG, capacity provider)

   Dev는 t3.small(2GiB)이라 **노드당 API 태스크가 1개**뿐이다. Prod의 surge 방식을 쓸 수 없으므로 축소 우선 방식으로 설정한다 (계획서 §2.1):

   ```hcl
   # 태스크 정의
   memoryReservation = 800
   memory            = 900     # 현재 1500 — t3.small 예산(~1000MiB)에 맞춰 하향

   # 서비스
   deployment_minimum_healthy_percent = 50    # desired 2 → 최소 1태스크
   deployment_maximum_percent         = 100   # 최대 2태스크 (노드당 1개)
   ```

   배포 시퀀스: `구2:신0 → 1:0 → 1:1 → 0:1 → 0:2`

   > ⚠️ `minimum_healthy_percent`를 100으로 두면 태스크를 먼저 내릴 수 없어 **배포가 교착 상태에 빠진다.** 반드시 50으로 낮춘다.

7. 구 Dev 노드 드레인 → 종료

### 검증
- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] Dev에서 rolling 배포가 정상 수행되는지 — **promote 게이트의 전제**
- [ ] 배포 중 `1:1`(구/신 공존) 구간이 실제로 관측되는지 — 버전 공존 검증
- [ ] **Dev API 실사용 메모리 실측** → 900이 적정한지 확인, 부족하면 cAdvisor task memory를 256 → 160으로 조여 100MiB 확보 (계획서 §4 To-Do 4)
- [ ] Dev RDS 자동 백업이 설정되었는지

### 롤백
단계별로 이전 엔드포인트 복원. Dev이므로 짧은 다운타임을 감수할 수 있다.

---

## Phase 9 — 접근 경로 정리

**목적**: bastion·WireGuard·SSH를 폐기하고 SSM으로 일원화한다.
**사용자 영향**: 없음 (개발자 워크플로는 변경됨)
**선행 조건**: Phase 5·7·8에서 **SSM 접속이 실제로 검증되어 있어야 한다.**

### 절차

1. **팀 전환 안내 및 준비**
   - 각자 AWS CLI + Session Manager Plugin 설치
   - IAM 권한 부여 (`ssm:StartSession` 등)
   - 자주 쓰는 포트 포워딩 스크립트 배포 (`scripts/connect-rds-prod.sh`, `connect-rds-dev.sh`)
2. **전환 기간 운영** (1~2주) — WireGuard와 SSM을 병행하며 팀이 SSM에 적응
3. **구 모니터링/NAT/VPN 노드 종료**
4. **SG 정리**
   - 22번 규칙 3곳 제거
   - WireGuard UDP 51820 제거 (현재 `0.0.0.0/0` 개방)
   - `trusted_ips` 변수 폐기
5. **키페어 의존 제거** — launch template에서 `key_name` 제외 (Phase 7에서 이미 제외했다면 확인만)
6. **SSM 세션 로그를 S3/CloudWatch로 설정** (접근 감사 기록)

### 검증
- [ ] 팀 전원이 SSM으로 노드 접속 가능
- [ ] RDS 포트 포워딩으로 DB 클라이언트 연결 가능
- [ ] 세션 로그가 실제로 남는지
- [ ] 22번·51820이 어디에도 열려 있지 않은지 (`aws ec2 describe-security-groups`로 확인)

### 롤백
SG 규칙 복원. 단 구 VPN 노드를 종료한 뒤라면 재구축이 필요하므로, **3번(노드 종료) 전에 팀 전환을 확실히 끝낸다.**

---

## Phase 10 — Secrets를 SSM Parameter Store로

**목적**: 비밀값이 Terraform state·태스크 정의 JSON·ECS 콘솔에 평문으로 남는 상태를 해소한다.
**사용자 영향**: 없음 (rolling 재배포)
**시점**: Phase 4의 rolling 배포가 충분히 안정화된 뒤. 태스크 정의를 건드리므로 다른 변경과 겹치지 않게 한다.

### 절차

1. **파라미터를 AWS CLI로 생성** (Terraform으로 만들지 않는다 — state에 평문이 다시 들어간다)
   ```bash
   aws ssm put-parameter --name /groble/prod/db-password --type SecureString --value '<값>' --key-id <kms-key>
   ```
2. 태스크 정의를 `environment` → `secrets`로 변경
   ```hcl
   secrets = [
     { name = "DB_PASSWORD", valueFrom = "arn:aws:ssm:...:parameter/groble/prod/db-password" }
   ]
   ```
3. **Task Execution Role에 `ssm:GetParameters` + KMS `Decrypt` 권한을 추가한다** ⚠️

   > 흔한 오해: 현재 `ssm:GetParameters`(`parameter/groble/*`)는 **Task Role**에 인라인으로 붙어 있고,
   > **Execution Role에는 없다**(`AmazonECSTaskExecutionRolePolicy` + `AmazonEC2ContainerRegistryPowerUser`뿐).
   > 태스크 정의의 `secrets` / `valueFrom`은 **Execution Role 권한으로 해석**되므로,
   > 권한을 추가하지 않으면 태스크가 `ResourceInitializationError`로 기동에 실패한다.
4. rolling 재배포
5. Grafana `GF_SECURITY_ADMIN_PASSWORD`도 동일하게 처리
6. Terraform 변수에서 평문 비밀값 제거

### 검증
- [ ] 태스크 정의 JSON에 평문 비밀값이 없는지
- [ ] 앱이 정상 기동하고 DB 연결이 되는지
- [ ] state 파일에서 비밀값이 사라졌는지 (`terraform state pull | grep -i password`)

### 롤백
이전 태스크 정의 리비전으로 `update-service`.

---

## Phase 11 — 잔재 정리 및 문서 갱신

**사용자 영향**: 없음

### 정리 대상

- [ ] CodeDeploy 애플리케이션 / 배포그룹 / IAM 역할 (Phase 4에서 남겼다면)
- [ ] **테스트 리스너(9443)** 및 관련 SG 규칙 — rolling에서는 사용하지 않음
- [ ] 사용하지 않는 Blue 타깃그룹
- [ ] `ecs-cluster` 모듈의 고정 사설 IP 변수 (`prod_instance_private_ip` 등)
- [ ] Ubuntu 기반 user_data 스크립트 3개
- [ ] `/opt/mysql-prod-data` 생성 로직 (fallback MySQL 잔재)
- [ ] 모니터링 노드의 NAT iptables·`source_dest_check` 설정

### 문서 갱신

- [ ] **CLAUDE.md 정정**
  - "ECS Task Role: EC2 describe" → 실제 정책과 불일치 (S3/KMS/SSM + 신규 `ec2:DescribeInstances`)
  - "Prometheus: S3 장기 저장(90일)" → **실제로 미사용**. 현재는 로컬 15일이 전부
  - EC2 인스턴스 표, 배포 전략, 네트워크 구성, Secrets 관리 전면 갱신
- [ ] `scripts/deploy-step.sh`가 여전히 유효한지 검토
- [ ] 계획서 §4의 남은 To-Do 상태 갱신
- [ ] Phase 7에서 실측한 **노드 복구 시간**을 계획서 §2.1에 반영

---

## 부록 A — Phase별 예상 소요와 권장 간격

| Phase | 작업 시간 | 다음 Phase까지 관찰 |
|---|---|---|
| 0 | 반나절 | — |
| 1 | 반나절 | 1주 (기준선 수집) |
| 2 | 1~2일 | 2~3일 |
| 3 | 1시간 | 1~2일 |
| 4 | 반나절 + 관찰 | **1주** (rolling 안정화) |
| 5 | 반나절 | 2~3일 |
| 6 | 1~2시간 | **1주** (결제 지표 확인) |
| 7 | 1일 | **1주** (instance refresh 검증 포함) |
| 8 | 1일 | 2~3일 |
| 9 | 전환 기간 1~2주 | — |
| 10 | 반나절 | 2~3일 |
| 11 | 1일 | — |

**전체 약 6~8주.** Phase 4·6·7 뒤의 관찰 기간을 줄이지 않는 것을 권한다 — 문제가 즉시 드러나지 않는 종류의 변경들이다.

---

## 부록 B — 각 Phase의 "되돌릴 수 없는 지점"

| Phase | 되돌릴 수 없게 되는 시점 | 그 전에 반드시 확인할 것 |
|---|---|---|
| 4 | 구 CodeDeploy 서비스 제거 | rolling 배포 1회 이상 성공, 서킷 브레이커 동작 |
| 6 | ElastiCache로 전환한 순간 | 저트래픽 시간대인지, 결제 지표 기준선 기록 |
| 7 | 구 Prod 인스턴스 종료 | 신 노드에서 태스크 정상 기동, Prometheus 타깃 등록, SSM 접속 |
| 8 | 구 Dev MySQL 컨테이너 제거 | RDS로 데이터 복원 완료 및 검증 |
| 9 | 구 VPN 노드 종료 | **팀 전원의 SSM 전환 완료** |

---

## 부록 C — 자주 쓸 확인 명령

```bash
# ECS 컨테이너 인스턴스 상태
aws ecs list-container-instances --cluster groble-cluster --profile groble-terraform
aws ecs describe-container-instances --cluster groble-cluster --container-instances <arn> --profile groble-terraform

# 서비스 배포 상태
aws ecs describe-services --cluster groble-cluster --services groble-prod-service --profile groble-terraform \
  --query 'services[0].deployments'

# 타깃그룹 헬스
aws elbv2 describe-target-health --target-group-arn <arn> --profile groble-terraform

# 노드 접속 (Phase 9 이후 표준 방법)
aws ssm start-session --target <instance-id> --profile groble-terraform

# RDS 포트 포워딩
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<rds-endpoint>"],"portNumber":["3306"],"localPortNumber":["13306"]}' \
  --profile groble-terraform
```
