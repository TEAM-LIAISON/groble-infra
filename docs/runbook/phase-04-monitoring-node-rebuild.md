# Phase 4 — 모니터링 노드 재구축

> [← Phase 3](./phase-03-nat-gateway.md) · [이관 절차 목차](README.md) · [다음: Phase 6 →](./phase-06-deployment-controller.md)

| | |
|---|---|
| **상태** | ✅ **완료** (2026-08-30) |
| **목적** | 현재 모니터링 노드는 public 2a에 있고 NAT·bastion·VPN을 겸직한다. private 2c의 AL2023 노드로 옮긴다 |
| **사용자 영향** | 없음 — 구 노드를 병존시킨 채 전환한다. **단 관측은 스택 이동 중 수 분 끊긴다** |
| **선행 조건** | [Phase 2](./phase-02-observability.md)(Grafana as-code 프로비저닝) 완료. **[Phase 6](./phase-06-deployment-controller.md)(배포 컨트롤러 전환)와는 무관하다** — 아래 참조 |
| **산출물 범위** | **관측 스택 이전까지.** 구 노드는 NAT·bastion·VPN 을 지고 계속 살아 있다 |
| **되돌리기** | DNS 레코드 되돌리기 (재배포 없음) |

> 모니터링 노드는 계획서 §0에 따라 **pet으로 유지**한다. ASG로 만들지 않는다.

---

## ✅ 완료 요약 (2026-08-30)

> **이 문서는 이미 끝난 작업의 기록이다.** 아래 절차는 다시 따라 할 것이 아니라, 지금 배포된 상태가
> 어떻게 만들어졌는지와 되돌리는 방법을 남겨둔 것이다.
> 다만 **모니터링 노드를 다시 교체할 때는 E·F 두 단계를 그대로 재사용한다** — 아래 "재사용할 절차" 참조.

**배포된 것**

| | |
|---|---|
| 신 노드 | **`groble-monitoring-v2-instance`** — ECS-optimized **AL2023**, **t3a.small**, **private 2c**, 고정 IP `10.0.12.100`, public IP 없음 |
| 구 노드 | `groble-monitoring-instance` → **`groble-nat-instance` 로 개명** (태그만 변경, ENI·LaunchTime 유지, egress 무중단) |
| DNS | Route 53 private hosted zone `internal.groble.im` + `otel.internal.groble.im` A 레코드 (TTL 60) |
| IAM | ECS Instance Role 에 `AmazonSSMManagedInstanceCore` (shared — **네 노드 전부**에 붙었다) |
| 앱 (이 리포) | prod·dev 태스크 정의의 `OTEL_EXPORTER_OTLP_ENDPOINT` → `http://otel.internal.groble.im:4318` (dev rev **1182** · prod rev **523**) |
| 앱 (앱 리포) | `loki.url` 을 같은 이름으로 — PR **#882**(dev) · **#883**(prod) |
| 제거 | `data "aws_instance" "shared_monitoring_instance"` · 정적 `aws_lb_target_group_attachment` 2개(`removed` 블록으로 state 에서만 분리) |
| ALB | 모니터링 타깃그룹 `deregistration_delay = 30` (기본 300 → 배포 시 관측 단절이 6분에서 크게 줄었다) |
| 비용 | EC2 3대 → **4대**, **+$17/월** (t3a.small) |

**검증 결과**

- ⭐ **앱 텔레메트리가 재배포 없이 신 노드로 이동했다** — 이 Phase 의 핵심 성과
- 메트릭 유입 production **174** series · development **17** series, 로그 유입 양쪽 확인
- `loki4j_drop_events_total = 0` (**유실 없음**). `send_errors_total = 9` 는 커넥션이 끊긴 순간의 실패로 재시도에 흡수됐다
- Prometheus 타깃 **16/16 up**, recording rule 정상
- Grafana 복원 — 대시보드 3 · 데이터소스 2(UID 고정, health 200) · 알림 규칙 14 · contact point 3
- **Grafana → SNS → Slack 경로 실증** (2026-08-30 20:09 KST) — 전환 작업이 스스로 만든
  `스크레이프 타깃 다운` 알림이 firing·resolved 양쪽 다 도달했다. 즉 private 서브넷의 신 노드가
  NAT 를 경유해 SNS 를 호출하는 경로가 살아 있다
- 네 노드 모두 SSM Online

**계획과 달랐던 점**

1. **E·F 순서를 뒤집었다** — 원래 "스택 이동 → DNS 변경"이었으나 **앱이 keep-alive 로 커넥션을
   재사용해 IP 를 고정**한다는 것이 확인되어 **"DNS 먼저 → 드레이닝으로 커넥션 끊기"** 가 됐다
2. **JVM DNS 캐시는 차단 조건이 아니었다** — TTL 은 이미 30초(JDK 17 기본값)였다.
   2026-08-29 RDS 사고의 원인도 DNS 캐시가 아니라 **커넥션 풀 수명**으로 정정됐다
   ([회신](../handoff/closed/jvm-dns-cache.md))
3. **WireGuard 로 신 노드 SSH 사전 확인을 하지 않았다** — SSM 이 첫 부팅부터 동작해 대안 경로를
   시험할 이유가 없었다. `key_name` 은 붙어 있다
4. **정적 타깃그룹 attachment 와 ECS 의 등록 관리가 충돌하는 것이 드러났다.** ECS 가 구 노드를
   빼는 순간 Terraform 이 다시 붙이려 해서 걷어냈다
5. **노드 타입이 `t3.small` 초안에서 `t3a.small` 로 바뀌었다** — 스펙 동일, 10% 저렴.
   ENI 가 2개(t3.small 은 3개)지만 모니터링 서비스가 전부 host 모드라 무해하다

**유실된 것** (E 를 지나며 SQLite 가 갈렸다 — 되돌려도 복구되지 않는다)

- Prometheus 로컬 15일치
- Grafana **사용자 계정 · 알림 silence · UI 로 만든 대시보드 4개**
- Grafana admin 비밀번호가 `terraform.tfvars` 값으로 **바뀌었다** — 드리프트가 이때 해소됐다

**남긴 것 · 다음으로 넘긴 것**

- 구 노드는 `DRAINING` 인 채 **NAT · bastion · WireGuard 를 계속 진다.**
  인스턴스 제거는 [Phase 3](./phase-03-nat-gateway.md) → [10](./phase-10-access-path.md) → [12](./phase-12-cleanup.md)
- **Loki→S3 가 NAT 를 타게 됐다.** S3 Gateway Endpoint 는 만들어 뒀으나 private RT 에 미연결
  (`attach_s3_endpoint_to_private_rt = false`). 병존이 몇 주로 길어지면 재검토할 것
- **다음 노드 교체 때는 SSM 이 안 될 가능성에 대비해 대안 경로를 먼저 확인하는 편이 낫다**

**재사용할 절차 — 다음 모니터링 노드 교체**

**[E](#e-dns-를-신-노드로-구-5-d) → [F](#f-ssm-확인--스택-이동-커넥션이-끊기며-전환이-일어난다) 두 단계면 끝난다.**
레코드 값을 신 노드로 바꾸고, 구 노드를 드레이닝해 커넥션을 끊는다. **앱 재배포가 필요 없다.**
(단 JVM `networkaddress.cache.ttl` 이 유한해야 한다 — 현재 30초)

**롤백**

DNS 레코드를 구 노드 IP 로 되돌린다 (재배포 없음). 단 위 "유실된 것"은 복구되지 않는다.

---

## 배포 컨트롤러 전환(Phase 6)과 순서를 맞바꾼 Phase 다

**원래 이것이 Phase 6, 배포 컨트롤러 전환이 Phase 4 였다.** 배포 컨트롤러 전환이
앱 측 차단 조건 4건(계획서 §3)에 막혀 있는 동안 이 Phase 는 진행할 수 있어서, 2026-08-30 에
번호를 맞바꿨다. 근거는 [이관 절차 목차](README.md#번호-이력--옛-문서pr-의-번호는-다를-수-있다) 에 있다.

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

> ✅ **해소됨 (2026-08-30, C단계).** 데이터소스를 제거했고, 신 노드는
> `groble-monitoring-v2-instance` 로 만들었다. 구 노드는 남은 역할에 맞춰
> **`groble-nat-instance` 로 개명**했다(태그만 변경 — `0 to add / 1 to change / 0 to destroy`,
> ENI·LaunchTime 유지, egress 무중단).
> ⚠️ Prometheus 가 Name 태그를 `instance_name` 라벨로 승격하므로 개명 시점에 그 노드의
> 시계열이 끊긴다. 규칙 의존은 0건이라 알람 영향은 없다.

### 2. `AmazonSSMManagedInstanceCore` 가 ECS Instance Role 에 없다

[iam-roles/main.tf:28](../../modules/infrastructure/iam-roles/main.tf#L28) 에는
`AmazonEC2ContainerServiceforEC2Role` + `AmazonEC2ContainerRegistryReadOnly` 뿐이다.
SSM 접속 확인은 **구 노드 폐기의 선행 조건**인데 이 정책 없이는 세션이 열리지 않는다.
additive 라 무영향이지만 **shared 환경 변경**이므로 모든 노드에 붙는다.

### 3. placement constraint 로는 스택 이동을 통제할 수 없다

모니터링 5개 서비스가 전부 `attribute:environment == monitoring` 이다
(`modules/services/monitoring/*/main.tf`). 신 노드에 같은 attribute 를 주면 ECS 가
두 노드 중 **어디에 놓을지 결정론적이지 않다.** host mode + desired 1 이라 "복제"가 아니라 "이동"이다.

→ **구 노드를 `DRAINING` 으로 전환해 밀어낸다** ([Phase 9](./phase-09-prod-asg.md) 6번과 같은 기법).
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

> **비밀번호가 바뀌었다.** `GF_SECURITY_ADMIN_PASSWORD` 는 SQLite 초기화 시점에만 적용되므로
> 전환 전 운영 비밀번호는 `terraform.tfvars` 값과 달랐다(드리프트). 신 노드에서 tfvars 값이
> **실제로 적용**되면서 드리프트가 해소됐다 — **지금은 tfvars 값이 실제 값이다.**
>
> - [x] tfvars 값으로 전환 — 팀에 사전 공지 완료
> - [ ] ~~UI 로 만든 대시보드 4개 export~~ — **하지 않았고, 유실됐다.**
>       다음 노드 교체 전에는 이 단계를 반드시 밟을 것

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

- [x] **dev** — 리비전 1182(이미지 `dev-563a416`, PR #882 머지분) 배포·유입 확인 (2026-08-30)
- [x] **prod** — 리비전 523(이미지 `prod-d17ee87`, PR #883 머지분) 배포·유입 확인 (2026-08-30)
- [x] 두 칸이 모두 채워지기 전에는 **E 에 진입하지 않는다** → 충족 후 진입했다

확인 기준은 **"아무 일도 일어나지 않는 것"** 이다 — 이름이 구 노드를 가리키므로
로그·메트릭이 전과 같은 곳으로 끊김 없이 계속 들어와야 한다.
- ⚠️ **사전 확인: JVM DNS 캐시 TTL** (계획서 §3-8, To-Do 12) — 무기한이면 F 가 재배포 없이는 반영되지 않아
  이 Phase 의 핵심 성과가 사라진다. **2026-08-29 RDS 8.4 스위치오버 때 JVM 이 구 IP 를 붙잡아
  7~8분간 쓰기가 실패한 전력이 있다** ([adhoc 런북 사고 1](./adhoc/rds-mysql-84-upgrade.md)) —
  즉 현재 TTL 은 사실상 무기한으로 봐야 한다.
  → 회신: [`handoff/closed/jvm-dns-cache.md`](../handoff/closed/jvm-dns-cache.md) — **차단 조건이 아니었다**(TTL 30초). 다만 keep-alive 때문에 E·F 순서가 바뀌었다

### D. 신 노드 생성

- **`t3a.small`**, **ECS-optimized AL2023**(AMI 는 SSM Parameter 로 참조), **private 2c**, public IP 없음, 고정 사설 IP `10.0.12.100`
  - t3.small 초안에서 바꿨다 — 스펙 동일·10% 저렴. ENI 만 2개인데 모니터링 서비스가 전부 host 모드라 무해하다
- **`Name` 태그는 구 노드와 다르게** (함정 1)
- **`Cluster = groble-cluster` 태그 필수** — 빠지면 Prometheus `ec2_sd` 가 **경고 없이** 스크레이프 목록에서 누락한다
- `environment = monitoring` 태그 + user_data 의 `ECS_INSTANCE_ATTRIBUTES={"environment":"monitoring"}`
- **`key_name` 유지** (함정 ③ — SSM 이 안 될 때의 유일한 대안)
- 인스턴스 프로파일은 A 에서 갱신된 것

### ⚠️ E·F 의 순서가 바뀌었다 — DNS 를 **먼저** 바꾼다 (2026-08-30)

원래는 E(스택 이동) → F(DNS 변경) 순이었다. **백엔드 회신으로 순서를 뒤집었다.**

**이유: 앱이 keep-alive 로 커넥션을 재사용해 IP 를 고정한다.**
레코드만 바꿔서는 옮겨가지 않는다 — 살아 있는 커넥션은 DNS 를 다시 조회하지 않는다.

| 레인 | 구현 | 왜 안 끊기나 |
|---|---|---|
| OTLP(메트릭) | OpenTelemetry Java exporter + OkHttp | 유휴 5분까지 재사용하는데 전송 주기가 60초라 **유휴로 빠질 틈이 없다** |
| 로그 | loki4j 1.5.1 | keep-alive 로 수초 간격 배치를 계속 보낸다 |

**커넥션을 끊어 줘야 재연결하면서 DNS 를 새로 조회한다.** 그 "끊는 행위"가 바로
구 노드의 수신 프로세스 중단 = 드레이닝이다. 그래서 **레코드를 먼저 바꿔 두고
드레이닝으로 커넥션을 끊는** 순서가 된다.

> DNS TTL 자체는 문제가 아니다 — **성공 30초 / 실패 10초**(JDK 17 기본값)로 이미 충분하다.
> 백엔드가 `-Dsun.net.inetaddr.ttl=60` 명시 설정 PR 을 별도로 올리고 있으나,
> **이 Phase 의 차단 조건은 아니다.** ([회신](../handoff/closed/jvm-dns-cache.md))

---

### E. DNS 를 신 노드로 (구 5-d)

- shared 의 `otel_target_private_ip` 를 **신 노드 IP(`10.0.12.100`)** 로 바꾼다
- **plan 이 `aws_route53_record.otel_internal` 의 `~ update in-place` 하나여야 한다.**
  그 외가 잡히면 중단
- **이 시점에는 아무 일도 일어나지 않는다** — 앱은 keep-alive 로 여전히 구 노드에 보낸다.
  그것이 정상이다

### F. SSM 확인 → 스택 이동 (커넥션이 끊기며 전환이 일어난다)

1. **SSM 접속 확인** — `aws ssm start-session --target <new-instance-id>`
   - 실패하면 여기서 멈춘다. 구 노드 폐기(Phase 10·12)의 선행 조건이다
2. **구 노드를 `DRAINING` 으로 전환** — 모니터링 태스크가 신 노드로 밀려난다 (함정 3)
   ```bash
   aws ecs update-container-instances-state --cluster groble-cluster \
     --container-instances <old-container-instance-arn> --status DRAINING
   ```
   - 구 노드의 collector·Loki 가 죽으면서 **앱의 keep-alive 커넥션이 끊긴다**
     → 다음 전송이 재연결하며 DNS 를 새로 조회 → **이미 신 노드를 가리키므로 그리로 정착한다.
     앱 재배포 불필요**
   - ⚠️ **관측이 수 분 끊긴다.** host mode + desired 1 이라 태스크가 하나씩 옮겨간다
   - 모니터링 타깃그룹은 `deregistration_delay = 30` 이므로(2026-08-30) 이 창이 6분에서 크게 줄어 있다
3. **ALB 타깃그룹은 손댈 필요가 없다** — Grafana ECS 서비스의 `load_balancer` 블록 때문에
   **ECS 가 등록·해제를 직접 관리한다.** 태스크가 옮겨가면 구 노드를 빼고 신 노드를 넣는다.
   → `monitor.groble.im` 접속 확인만 하면 된다
   > ⚠️ 2026-08-30 에 정적 `aws_lb_target_group_attachment` 2개를 걷어냈다. ECS 가 구 노드를
   > 빼는 순간 Terraform 이 "다시 붙여야 한다"고 판단해 충돌이 드러났기 때문이다.
   > `removed` 블록으로 state 에서만 분리했다 — destroy 하면 Grafana 가 ALB 에서 빠진다.
4. Grafana 로그인 (**비밀번호가 tfvars 값으로 바뀌어 있다**)
5. **구 노드를 관측으로 되돌린다** — 드레이닝하면 DAEMON 도 함께 빠지는데,
   **구 노드는 여전히 NAT 를 지고 있어 지표가 없으면 안 된다.**
   ```bash
   # 관측 스택이 되돌아오지 못하게 attribute 부터 지운다
   aws ecs delete-attributes --cluster groble-cluster \
     --attributes "name=environment,targetId=<old-container-instance-arn>"
   # 그다음 ACTIVE 로. DAEMON 2종만 돌아온다
   aws ecs update-container-instances-state --cluster groble-cluster \
     --container-instances <old-container-instance-arn> --status ACTIVE
   ```
   - **순서가 중요하다.** attribute 를 남긴 채 ACTIVE 로 되돌리면, 태스크가 죽어 재배치될 때
     관측 스택이 구 노드로 다시 흘러갈 수 있다 (양쪽 다 `environment=monitoring` 이므로)
   - node-exporter·cAdvisor 는 placement constraint 가 없어 attribute 와 무관하게 배치된다
   - 이걸 건너뛰면 `ec2_sd` 가 구 노드를 계속 발견하는데 스크레이프는 실패해
     **down 타깃 2개가 영구히 남는다** (실제 장애를 가리는 노이즈가 된다)

### 전환 직후 공동 확인 (백엔드와 함께)

- [x] 신 노드에 **메트릭 유입** — production 174 series / development 17 series
- [x] 신 노드에 **로그 유입** — 양쪽 환경 모두 확인
- [x] **loki4j drop 지표** — `loki4j_drop_events_total = 0` (**유실 없음**). `send_errors_total = 9` 는 커넥션이 끊긴 순간의 실패이며 재시도로 흡수됐다

> 이후 모니터링 노드를 다시 교체할 때도 **같은 두 단계(레코드 변경 → 구 수신 중단)를
> 반복하면 된다.** 앱 재배포가 필요 없는 것이 이 Phase 의 진짜 성과다.

### G. 구 노드 정리 — 이번엔 여기까지만

- 구 노드는 `DRAINING` 인 채로 둔다. **NAT/bastion/WireGuard 는 살아 있다**
- 인스턴스 제거는 [Phase 3](./phase-03-nat-gateway.md)(NAT) → [Phase 10](./phase-10-access-path.md)(접근 경로) → [Phase 12](./phase-12-cleanup.md)(정리) 로 넘어간다
- 그동안 EC2 가 3대 → **4대**가 된다 (t3a.small 월 **$17.08** 추가)

## 검증

- [x] **A 후** SSM 정책 부착 확인 — 네 노드 모두 SSM Online
- [x] **C 후** 앱 텔레메트리가 여전히 구 노드로 — 동작 변화 없음 확인
- [x] **C 후** prod·dev `terraform plan` No changes
- [x] **C 게이트** — dev·prod 둘 다 배포·유입 확인 완료
- [x] **D 후** ECS 등록(agent 1.106.1) · `ec2_sd` 가 `10.0.12.100` 자동 발견
- [ ] ~~**E 전** WireGuard 로 신 노드 SSH~~ — **하지 않았다.** SSM 이 첫 부팅부터 동작해
      대안 경로를 시험할 이유가 없었다. `key_name` 은 붙어 있으므로 필요하면 쓸 수 있다.
      **다음 노드 교체 때는 SSM 이 안 될 가능성에 대비해 먼저 확인하는 편이 낫다**
- [x] **E 후** Grafana 복원 — 대시보드 3 · 데이터소스 2(UID 고정, health 200) · 알림 규칙 14 · contact point 3(`sns-critical`·`sns-warning` 포함)
- [x] **E 후** Prometheus 타깃 **16/16 up**, recording rule 정상
- [x] **E 후** Loki 신규 로그 유입 지속 (S3 경로가 NAT 를 타게 된 뒤에도)
- [x] **F 후** 앱 텔레메트리가 **재배포 없이** 신 노드로 이동 — 이 Phase 의 핵심 성과
- [x] **Grafana 알림 → SNS → Slack 경로 (의존 ②) — 검증됨** (2026-08-30 20:09 KST).
      강제 발화 없이 **전환 작업 자체가 만든 알림으로 확인됐다.** 드레이닝 중 구 노드의
      cadvisor·node-exporter 가 빠지면서 `스크레이프 타깃 다운` 이 발화했고, 복귀 후
      `[resolved]` 까지 Slack 에 도달했다.
      - **CloudWatch 백스톱이 아니라 Grafana 경로임을 확인했다** — CloudWatch 알람 19개는
        전부 `groble-*` 영문 이름이고 이 이름이 없다. Slack 문구가 Grafana 규칙의
        `summary`·`runbook` annotation 과 글자 그대로 일치하며, 템플릿 변수가 `2개` 로 렌더링됐다
      - **firing 과 resolved 양쪽 다 도달한다.** resolve 쪽이 더 잘 누락되는데 그것까지 왔다
      - 즉 **신 노드가 private 서브넷에서 NAT 를 경유해 SNS 를 호출하는 경로가 살아 있다**

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

[← Phase 3 — NAT Gateway 전환](./phase-03-nat-gateway.md) · [이관 절차 목차](README.md) · [다음: Phase 6 — 배포 컨트롤러 전환 →](./phase-06-deployment-controller.md)
