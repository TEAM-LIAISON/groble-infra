# Phase 4 — 모니터링 노드 재구축

> [← Phase 3](./phase-03-nat-gateway.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 5 →](./phase-05-deployment-controller.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | 현재 모니터링 노드는 public 2a에 있고 NAT·bastion·VPN을 겸직한다. private 2c의 AL2023 노드로 옮긴다 |
| **사용자 영향** | 없음 — 구 노드를 병존시킨 채 전환한다. **단 관측은 스택 이동 중 수 분 끊긴다** |
| **선행 조건** | [Phase 2](./phase-02-observability.md)(Grafana as-code 프로비저닝) 완료. **[Phase 5](./phase-05-deployment-controller.md)(배포 컨트롤러 전환)와는 무관하다** — 아래 참조 |
| **산출물 범위** | **관측 스택 이전까지.** 구 노드는 NAT·bastion·VPN 을 지고 계속 살아 있다 |
| **되돌리기** | DNS 레코드 되돌리기 (재배포 없음) |

> 모니터링 노드는 계획서 §0에 따라 **pet으로 유지**한다. ASG로 만들지 않는다.

---

## 배포 컨트롤러 전환(Phase 5)과 순서를 맞바꾼 Phase 다

**원래 이것이 Phase 5, 배포 컨트롤러 전환이 Phase 4 였다.** 배포 컨트롤러 전환이
앱 측 차단 조건 4건(계획서 §3)에 막혀 있는 동안 이 Phase 는 진행할 수 있어서, 2026-08-30 에
번호를 맞바꿨다. 근거는 [이관 절차 목차](../infra-ha-migration-runbook.md#4↔5-를-맞바꾼-이유-2026-08-30) 에 있다.

**둘 사이에 의존이 없다.** 아래 C 단계의 재배포는 **CodeDeploy Blue/Green 으로 해도 무방**하다
(원래 문구는 "rolling 을 활용"이었으나 기능적 의존이 아니다).

## Phase 3 미완(모니터링 노드가 여전히 NAT) 상태에서 진행해도 되는가 — 된다

**이 Phase 는 NAT/bastion/WireGuard 역할을 건드리지 않는다.**
`update-container-instances-state --status DRAINING` 은 **ECS 태스크 배치**만 바꾼다.
NAT(호스트 iptables + `source_dest_check = false`)와 sshd·WireGuard 는 ECS 태스크가 아니라
호스트 레벨이므로, 드레이닝해도 구 인스턴스는 그대로 패킷을 넘긴다.

**오히려 Phase 3 보다 먼저 하는 편이 낫다.** 지금 t3.small 한 대가 관측 스택 4개 + NAT + bastion +
VPN 을 모두 지고 있고, Prometheus 는 512 MiB 하드리밋에서 **실제로 OOM 으로 죽은 전력**이 있다.
전 private 서브넷의 egress 가 걸린 노드가 죽은 적 있는 프로세스와 메모리를 나눠 쓰고 있는 상태다.
스택을 빼내면 NAT 노드가 NAT·bastion 전용이 되어 가벼워진다.

### 다만 새로 생기는 의존 3건

| # | 무엇 | 판단 |
|---|---|---|
| **①** | **Loki→S3 가 NAT 를 타기 시작한다.** 지금 Loki 는 public 서브넷이라 IGW 로 직행하는데, private 로 옮기면 NAT 경유가 된다. S3 Gateway Endpoint 는 [Phase 3-a](./phase-03-nat-gateway.md) 에서 만들어 뒀지만 **private RT 에 미연결**(`attach_s3_endpoint_to_private_rt = false`) | **받아들인다.** 스위치 ②를 앞당기면 private 서브넷의 S3 연결이 한 번 끊기고 거기엔 **prod 앱 파일 업로드**가 포함된다. 로그 볼륨은 t3.small NAT 가 감당할 수준이다.<br>**병존이 몇 주로 길어지면 재검토할 것** — 이 스위치는 외부 업체 허용목록과 **무관**하다(S3 트래픽은 업체로 가지 않는다) |
| **②** | **Prometheus `ec2_sd` 와 Grafana 의 SNS contact point 가 NAT 의존이 된다.** 둘 다 AWS API 를 인터넷으로 호출한다 | 백스톱이 이미 있다 — [Phase 1](./phase-01-alarm-backstop.md) 의 CloudWatch→SNS→Chatbot 은 전부 AWS 쪽이라 VPC 를 타지 않는다. "관측 스택이 죽었을 때"가 그 백스톱의 존재 이유다 |
| **③** | **신 노드에 락아웃될 수 있다.** public IP 가 없어 진입 경로가 SSM(NAT 경유)과 WireGuard(`10.6.0.0/24` → 22) 뿐이고 양쪽 다 구 노드를 거친다 | **`key_name` 을 유지**하고, SG 22번이 `10.6.0.0/24` 에서 열려 있는지([security-groups/main.tf:149](../../modules/infrastructure/security-groups/main.tf#L149)) **신 노드 생성 전에 실제 접속으로** 확인한다. user_data 가 잘못되면 재생성 말곤 방법이 없다 |

---

## ⚠️ 착수 전에 해소해야 하는 것 4건

런북 v1 의 1→6 순서를 그대로 가면 1번에서 바로 깨진다. 아래를 먼저 처리한다.

### 1. 신 노드에 같은 `Name` 태그를 달면 prod·dev 의 `terraform plan` 이 실패한다

[prod/main.tf:99](../../environments/prod/main.tf#L99) · [dev/main.tf:84](../../environments/dev/main.tf#L84) 가
`tag:Name = "groble-monitoring-instance"` + running 으로 인스턴스를 조회한다.
병존 순간 매치가 2개가 되어 *"query returned more than one result"* 로 죽는다.

→ 신 노드는 **다른 Name 태그**를 쓴다. 근본 해소는 **5-b(DNS 간접화)로 이 데이터소스를 없애는 것**이며,
   이 데이터소스의 **유일한 용도가 OTLP 엔드포인트**다. 그래서 아래 절차는 5-b 를 노드 생성보다 앞에 둔다.

### 2. `AmazonSSMManagedInstanceCore` 가 ECS Instance Role 에 없다

[iam-roles/main.tf:28](../../modules/infrastructure/iam-roles/main.tf#L28) 에는
`AmazonEC2ContainerServiceforEC2Role` + `AmazonEC2ContainerRegistryReadOnly` 뿐이다.
SSM 접속 확인은 **구 노드 폐기의 선행 조건**인데 이 정책 없이는 세션이 열리지 않는다.
additive 라 무영향이지만 **shared 환경 변경**이므로 모든 노드에 붙는다.

### 3. placement constraint 로는 스택 이동을 통제할 수 없다

모니터링 5개 서비스가 전부 `attribute:environment == monitoring` 이다
(`modules/services/monitoring/*/main.tf`). 신 노드에 같은 attribute 를 주면 ECS 가
두 노드 중 **어디에 놓을지 결정론적이지 않다.** host mode + desired 1 이라 "복제"가 아니라 "이동"이다.

→ **구 노드를 `DRAINING` 으로 전환해 밀어낸다** ([Phase 7](./phase-07-prod-asg.md) 6번과 같은 기법).
   attribute 는 양쪽 노드에 다 두고, 배치는 드레이닝으로 강제한다.

### 4. AL2023 용 user_data 가 아직 없다

현재 `user_data/monitoring_user_data.sh` 는 **Ubuntu + ECS 에이전트 수동 설치**다.
AL2023 ECS-optimized 는 ecs-init 이 내장이라 완전히 다른 스크립트가 필요하다.

> 부수 효과로 **credential 프록시 iptables 문제가 구조적으로 해소된다** —
> 재부팅 시 태스크 IAM 롤이 조용히 깨지던 것, 과거 **Loki S3 적재 실패의 원인**이던 그것이다.

---

## ⚠️ 이 Phase 에서 유실되는 것 (런북 v1 에 누락돼 있었다)

`/opt/grafana/data` 의 SQLite 는 노드 로컬이고, 신 노드에서는 **새로 만들어진다.**

| | 결과 |
|---|---|
| 대시보드 3개 · 데이터소스 · 알림 규칙 | ✅ 이미지의 provisioning 으로 복원 |
| Loki 로그 | ✅ S3 에 있다 |
| Prometheus 로컬 15일치 | ❌ 유실 — **수용** |
| **Grafana admin 비밀번호** | ⚠️ **바뀐다** — 아래 |
| 사용자 계정 · 알림 silence · **UI 로 만든 기존 대시보드 4개** | ❌ 유실 |

> **비밀번호가 바뀐다는 것을 착수 전에 팀에 알린다.**
> `GF_SECURITY_ADMIN_PASSWORD` 는 SQLite 초기화 시점에만 적용되기 때문에 현재 운영 비밀번호는
> `terraform.tfvars` 값과 **다르다**(드리프트). 신 노드에서는 tfvars 값이 **실제로 적용**되므로,
> 전환 후 **지금 쓰는 비밀번호로는 로그인이 안 된다.**
>
> - [ ] tfvars 의 값이 팀이 공유 가능한 값인지 확인 (아니면 전환 전에 교체)
> - [ ] 살릴 대시보드가 있으면 **UI 로 만든 4개를 지금 export** 해 둔다

---

## 절차

1·2·3번 함정 때문에 순서를 재배열했다.

### A. ECS Instance Role 에 `AmazonSSMManagedInstanceCore` 추가

- 환경: `shared`. additive 이며 무영향
- 이것 없이는 B~F 를 다 해도 신 노드에 들어갈 수 없다

### B. 5-a — private hosted zone 생성 (신 노드 생성 **전에**)

- Route 53 private hosted zone `internal.groble.im` 생성 + VPC 연결
- `otel.internal.groble.im` A 레코드를 **구 노드 IP(`10.0.1.193`)** 로 등록, **TTL 60초**
- 이 시점에는 아무것도 이 이름을 쓰지 않는다 — 무영향

### C. 5-b — OTLP 엔드포인트를 DNS 로 간접화

- prod·dev 의 `otel_exporter_endpoint` 를 IP → `http://otel.internal.groble.im:4318`
- **`data "aws_instance" "shared_monitoring_instance"` 를 제거한다** → 위 함정 1번이 여기서 해소된다
- **이 시점에도 트래픽은 여전히 구 노드로 간다 — 동작 변화 없이 간접화만 도입한다**

#### ⚠️ 전송 주소는 두 곳에 있다. 둘 다 바꿔야 한다

앱은 목적지를 둘 가지며 **로그는 otelcol 을 거치지 않고 Loki 에 직접 간다.**

| 설정 | 목적지 | 이 값을 정하는 곳 | 누가 바꾸나 |
|---|---|---|---|
| `loki.url` | Loki `:3100` | **앱 yml 뿐** — 태스크 정의에 LOKI 환경변수가 없다 | **앱 리포지토리 PR** |
| `otel.exporter.otlp.endpoint` | otelcol `:4318` | **태스크 정의의 `OTEL_EXPORTER_OTLP_ENDPOINT`** — 환경변수가 yml 을 이긴다 | **이 리포지토리** |

한쪽만 바꾸면 로그나 메트릭 중 하나만 옮겨간다.

#### 🚧 **게이트 — 재배포가 실제로 끝나야 E 로 갈 수 있다**

**Terraform apply 만으로는 앱에 반영되지 않는다.** 태스크 정의 리비전이 하나 생길 뿐이고
`lifecycle { ignore_changes = [task_definition] }` 때문에 서비스는 구 리비전을 계속 돈다.

> CD 워크플로가 `describe-task-definition --task-definition <family>`(리비전 미지정 = **최신 ACTIVE**)
> 를 읽어 이미지만 갈아끼우므로, **Terraform 이 등록한 리비전이 다음 배포의 기반**이 된다.
> 즉 apply → (앱 배포) 순서면 자동으로 실려 간다.
>
> ⚠️ 그래서 **apply 전에 `terraform.tfvars` 의 `spring_app_image` 를 실행 중 이미지와 맞춰야 한다.**
> 낡은 값을 둔 채 apply 하면 그 낡은 이미지가 family 의 최신 리비전이 되어,
> "리비전 미지정 배포"가 그것을 띄운다.

**배포되지 않은 환경은 여전히 구 노드의 IP 를 직접 보고 있다.
E 에서 스택이 신 노드로 옮겨가는 순간 그 환경의 관측이 통째로 끊기고,
F(레코드 값 변경)는 DNS 를 쓰는 쪽만 따라오므로 구해주지 못한다.**

- [ ] **dev** — Terraform apply + 앱 배포 완료, Loki·Prometheus 유입 확인
- [ ] **prod** — Terraform apply + 앱 배포 완료, Loki·Prometheus 유입 확인
- [ ] 두 칸이 모두 채워지기 전에는 **E 에 진입하지 않는다**

확인 기준은 **"아무 일도 일어나지 않는 것"** 이다 — 이름이 구 노드를 가리키므로
로그·메트릭이 전과 같은 곳으로 끊김 없이 계속 들어와야 한다.
- ⚠️ **사전 확인: JVM DNS 캐시 TTL** (계획서 §3-8, To-Do 12) — 무기한이면 F 가 재배포 없이는 반영되지 않아
  이 Phase 의 핵심 성과가 사라진다. **2026-08-29 RDS 8.4 스위치오버 때 JVM 이 구 IP 를 붙잡아
  7~8분간 쓰기가 실패한 전력이 있다** ([adhoc 런북 사고 1](./adhoc/rds-mysql-84-upgrade.md)) —
  즉 현재 TTL 은 사실상 무기한으로 봐야 한다.
  → 요청서: [`handoff/rolling-deploy-prerequisites.md`](../handoff/rolling-deploy-prerequisites.md) §3 (문항 9·10)

### D. 신 노드 생성

- `t3.small`, **ECS-optimized AL2023**(AMI 는 SSM Parameter 로 참조), **private 2c**, public IP 없음, 고정 사설 IP
- **`Name` 태그는 구 노드와 다르게** (함정 1)
- **`Cluster = groble-cluster` 태그 필수** — 빠지면 Prometheus `ec2_sd` 가 **경고 없이** 스크레이프 목록에서 누락한다
- `environment = monitoring` 태그 + user_data 의 `ECS_INSTANCE_ATTRIBUTES={"environment":"monitoring"}`
- **`key_name` 유지** (함정 ③ — SSM 이 안 될 때의 유일한 대안)
- 인스턴스 프로파일은 A 에서 갱신된 것

### E. SSM 확인 → 스택 이동

> 🚧 **진입 전 확인: C 의 게이트 두 칸(dev·prod 배포)이 모두 채워졌는가.**
> 배포되지 않은 환경은 이 단계에서 관측이 끊긴다.

1. **SSM 접속 확인** — `aws ssm start-session --target <new-instance-id>`
   - 실패하면 여기서 멈춘다. 구 노드 폐기(Phase 9·11)의 선행 조건이다
2. **구 노드를 `DRAINING` 으로 전환** — 모니터링 태스크가 신 노드로 밀려난다 (함정 3)
   ```bash
   aws ecs update-container-instances-state --cluster groble-cluster \
     --container-instances <old-container-instance-arn> --status DRAINING
   ```
   - ⚠️ **관측이 수 분 끊긴다.** host mode + desired 1 이라 태스크가 하나씩 옮겨간다
   - 모니터링 타깃그룹은 `deregistration_delay = 30` 이므로(2026-08-30) 이 창이 6분에서 크게 줄어 있다
3. ALB 모니터링 타깃그룹을 신 노드로 재연결 → `monitor.groble.im` 접속 확인
4. Grafana 로그인 (**비밀번호가 tfvars 값으로 바뀌어 있다**)

### F. 5-d — DNS 를 신 노드로

- `otel.internal.groble.im` 레코드 값을 **신 노드 IP** 로 변경
- 60초 내 트래픽이 신 노드로 이동. **앱 재배포 없음**
- 이후 모니터링 노드를 다시 교체할 때는 **F 만 반복하면 된다** — 이 간접화가 이 Phase 의 진짜 성과다

### G. 구 노드 정리 — 이번엔 여기까지만

- 구 노드는 `DRAINING` 인 채로 둔다. **NAT/bastion/WireGuard 는 살아 있다**
- 인스턴스 제거는 [Phase 3](./phase-03-nat-gateway.md)(NAT) → [Phase 9](./phase-09-access-path.md)(접근 경로) → [Phase 11](./phase-11-cleanup.md)(정리) 로 넘어간다
- 그동안 EC2 가 3대 → **4대**가 된다 (t3.small 월 ~$15 추가)

## 검증

- [ ] **A 후** SSM 정책이 붙었는지 (`aws iam list-attached-role-policies`)
- [ ] **C 후** 앱 로그·트레이스가 **여전히 구 노드**로 들어오는지 — 간접화 자체의 검증
- [ ] **C 후** prod·dev `terraform plan` 이 깨끗한지 (데이터소스 제거 확인)
- [ ] **C 게이트** — dev·prod **둘 다** 앱 배포까지 끝나고 Loki·Prometheus 유입이 확인됐는지.
      **한 칸이라도 비면 E 로 가지 않는다**
- [ ] **D 후** 신 노드가 ECS 클러스터에 등록되고 `Cluster` 태그로 `ec2_sd` 에 잡히는지
- [ ] **E 전** WireGuard 로 신 노드 SSH 가 되는지 (락아웃 방지 — SSM 실패 시의 대안)
- [ ] **E 후** Grafana 대시보드 3개 · 데이터소스 · 알림 규칙이 프로비저닝으로 복원됐는지
- [ ] **E 후** Prometheus 타깃이 `ec2_sd` 로 전부 잡히는지 (`groble:*` recording rule 12건 포함)
- [ ] **E 후** Loki 에 신규 로그가 계속 쌓이는지 — **S3 경로가 NAT 를 타게 됐으므로 특히 확인** (의존 ①)
- [ ] **F 후** 60초 내 앱 트레이스·로그가 **신 otelcol** 로 들어오는지 — **재배포 없이** 옮겨졌는지가 핵심
- [ ] Grafana 알림 1건을 강제 발화시켜 SNS→Slack 이 NAT 경유로도 나가는지 (의존 ②)

## 롤백

| 시점 | 방법 |
|---|---|
| **F 이후** | DNS 레코드를 구 노드 IP 로 되돌린다 (재배포 없음) |
| **E 이후** | 구 노드를 `ACTIVE` 로 되돌리고 신 노드를 `DRAINING` → 스택이 구 노드로 복귀 |
| **C 이후** | DNS 가 구 노드를 가리키므로 되돌릴 것이 없다 |
| **A·B** | 리소스 삭제 (무영향) |

> 되돌려도 복구되지 않는 것: **Prometheus 로컬 15일치**, **Grafana 사용자 계정·silence·UI 대시보드 4개**.
> E 를 지나는 순간 SQLite 가 갈린다.

---

[← Phase 3 — NAT Gateway 전환](./phase-03-nat-gateway.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 5 — 배포 컨트롤러 전환 →](./phase-05-deployment-controller.md)
