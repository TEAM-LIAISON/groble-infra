# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **이 문서는 "현재 배포되어 있는 상태"를 기술한다.** 진행 예정인 대규모 개선의 To-Be 구조는
> `docs/`의 계획 문서에 있으며, 아직 반영되지 않았다. 아래 [진행 중인 인프라 개선](#진행-중인-인프라-개선)을 먼저 읽을 것.

## Project Overview

This is **groble-infra**, a Terraform-based AWS infrastructure project for the Groble application. It uses a 3-layer modular architecture deployed across shared, monitoring, development, and production environments on AWS (ap-northeast-2).

---

## 진행 중인 인프라 개선

**단일 EC2(pet) 구조 → ASG 기반 다중 인스턴스(cattle) 구조로 전환하는 대규모 개선이 설계 완료 상태다.**
인프라를 수정하기 전에 아래 문서를 확인하고, 변경이 계획과 충돌하지 않는지 검토할 것.

| 문서 | 내용 |
|---|---|
| [`docs/README.md`](docs/README.md) | **문서 진입점** — 무엇을 언제 여는가, 폴더·상태 어휘 규칙 |
| [`docs/infra-ha-improvement-plan.md`](docs/infra-ha-improvement-plan.md) | 무엇을 왜 바꾸는가 (설계·결정 근거) |
| [`docs/infra-ha-migration-runbook.md`](docs/infra-ha-migration-runbook.md) | 어떤 순서로 이관하는가 — **목차·공통 원칙·부록** |
| [`docs/runbook/`](docs/runbook/) | Phase 0~11 각각의 상세 절차·검증·롤백 (Phase당 1개 파일). `adhoc/`는 Phase 순서와 무관한 단발 작업 |
| [`docs/handoff/README.md`](docs/handoff/README.md) | 백엔드에 보낸 요청·질의와 **회신 대기 현황** (`closed/`는 종결분) |
| [`docs/infra-future-improvements.md`](docs/infra-future-improvements.md) | 이번 범위 밖 항목 (우선순위·트리거) |
| [`docs/monitoring-config-baking.md`](docs/monitoring-config-baking.md) | 모니터링 config baking 구조 |

**주요 방향** (상세는 계획 문서 참조):
ASG + Capacity Provider managed draining · ECS-optimized AMI(AL2023) · 전 구성요소 2c AZ 정렬 ·
NAT Gateway · ElastiCache/RDS로 상태 외부화 · CodeDeploy Blue/Green → ECS rolling ·
SSM Session Manager(bastion·WireGuard 폐기) · Terraform state를 S3로

**진행 상황**: **Phase 0 완료** (state를 S3로 이전 — 아래 [Terraform Operations](#terraform-operations) 참조).
**Phase 1 완료** — CloudWatch 알람 19개가 SNS→AWS Chatbot을 거쳐 Slack 2채널
(`#groble-alert` 긴급 / `#groble-alert-dev`)로 전달된다. 임계치는 실측 기준선으로 확정했다
(계획서 §2.1 "트래픽·자원 기준선").
**Phase 2 진행 중** — 2-0(API 워킹셋 측정) · 2-1(Prometheus `ec2_sd_config` 전환) ·
2-2(Grafana 프로비저닝 as-code) **배포·검증까지 완료**. `memoryReservation` 확정으로 Phase 7 차단이 풀렸다.
남은 것은 ① NoData로 죽어 있는 JVM 힙 알람 수정 ② 백엔드 지표 3종을 받은 뒤 알림 R10~R14. 상세와 이어받기는
[`docs/runbook/phase-02-observability.md`](docs/runbook/phase-02-observability.md)에 있다.
**Phase 3 진행 중** — 3-a(EIP `15.165.223.110` 확보 + S3 엔드포인트 생성)까지 apply 했다.
**아웃바운드 경로는 아직 바뀌지 않았다** (전환 스위치 3개가 전부 off). 남은 차단 조건은
**[외부 업체 허용목록에 이 IP 를 등록](docs/handoff/egress-ip-allowlist.md)하는 것**이며,
등록 완료 회신이 오면 스위치를 순서대로 켠다. 상세는
[`docs/runbook/phase-03-nat-gateway.md`](docs/runbook/phase-03-nat-gateway.md)에 있다.
Phase 4부터는 미착수다.
Phase와 독립적인 [RDS MySQL 8.4 업그레이드](docs/runbook/adhoc/rds-mysql-84-upgrade.md)는
**2026-08-29 전환 완료**했다 (확장 지원 과금 $178.56/월 중단).
구 인스턴스도 같은 날 삭제했고, 최종 스냅샷 `groble-prod-mysql-80-final`(8.0.45)만 남아 있다.

> **진행 상태의 단일 진실은 [이관 절차 목차](docs/infra-ha-migration-runbook.md)의 순서 요약 표다.**
> 이 문단은 그 요약일 뿐이므로, 상태가 바뀌면 표를 먼저 고칠 것.

Phase 2가 바꾼 것은 아래 [Monitoring Stack](#monitoring-stack-모두-host-mode-networking)에
반영했고, **그 밖의 서술은 여전히 As-Is다.**

---

## Key Commands

### Terraform Operations
각 environment 디렉토리에서 실행:
```bash
terraform init
terraform plan
terraform apply
terraform destroy
terraform show
```

**state는 S3에 있다** (`groble-terraform-state`, ap-northeast-2). 마이그레이션 Phase 0에서 로컬 파일에서 이전했다.

- 환경별 `backend.tf`가 backend를 정의한다. **S3 네이티브 잠금**(`use_lockfile`)을 쓰므로 DynamoDB 잠금 테이블은 없다
- 환경 간 참조(`data "terraform_remote_state"`)도 S3를 본다 — `prod` / `dev` / `monitoring`의 `main.tf`
- 객체는 SSE-KMS(`alias/groble/terraform-state`)로 암호화되고 versioning으로 이력이 남는다
- 버킷 정책이 접근 주체를 Terraform 실행 SSO 역할로 한정한다. **ECS Task Role은 `AmazonS3FullAccess`를 갖고 있지만 이 버킷은 거부된다**

⚠️ **Terraform 1.10+ 가 필요하다** (`use_lockfile` 요건). 리포지토리는 `.terraform-version`으로 **1.15.8**을 고정한다.
⚠️ **Phase 10 전까지 state에는 DB·Grafana 비밀번호가 평문으로 들어 있다.** 버킷을 시크릿 저장소로 취급할 것.

state 버킷·KMS 키·CloudTrail은 **Terraform이 관리하지 않는다** — "state를 담을 버킷의 state를 어디에 둘 것인가"라는 순환을 피하려고 AWS CLI로 만들었다. 정책 원본은 [`bootstrap/`](bootstrap/README.md)에 있다.

### AWS Profile
모든 작업에 `groble-terraform` AWS 프로필 필요:
```bash
aws configure --profile groble-terraform
```

## Architecture & Structure

### 3-Layer Architecture
1. **Infrastructure Layer** (shared): VPC, Security Groups, ALB, IAM Roles, Route53, RDS MySQL, WAF
2. **Platform Layer** (shared): ECS Cluster, ECR Registry, CodeDeploy
3. **Service Layer** (dev/prod/monitoring): Spring Boot API, MySQL, Redis, Monitoring Stack

### Deployment Order (Critical)
**반드시 이 순서대로 배포:**
1. `environments/shared` — VPC, SG, ALB, IAM, ECS Cluster, EC2 인스턴스 3대, CodeDeploy, WAF
2. `environments/monitoring` — Grafana, Prometheus, Loki, OpenTelemetry, Node Exporter, cAdvisor, RDS Exporter
3. `environments/dev` — Dev ECR, MySQL(컨테이너), Redis, Spring Boot API
4. `environments/prod` — Prod ECR, RDS MySQL(관리형), Redis, Spring Boot API

### Directory Structure
```
environments/
  shared/          # 공유 인프라 (VPC, SG, ALB, IAM, ECS, CodeDeploy, WAF)
  monitoring/      # 모니터링 스택 (Grafana, Prometheus, Loki, OTEL)
  dev/             # 개발 환경 서비스 (MySQL컨테이너, Redis, API)
  prod/            # 프로덕션 환경 서비스 (RDS MySQL, Redis, API)
modules/
  infrastructure/  # VPC, security-groups, iam-roles, load-balancer, rds-mysql, route53
  platform/        # ecs-cluster, ecr, codedeploy
  security/        # waf (AWS WAF v2)
  observability/   # alerting(SNS+Chatbot), alb-alarms, rds-alarms — 계층을 가로지르는 알람
  services/
    production/    # api-service, redis-service
    development/   # api-service, mysql-service, redis-service
    monitoring/    # grafana, prometheus, loki, otelcol, node-exporter, cadvisor, rds-exporter
shared/            # 공통 변수 정의 및 프로바이더 설정
bootstrap/         # Terraform이 관리하지 않는 부트스트랩 리소스의 정책 원본 (state 버킷·KMS·CloudTrail)
docs/              # 인프라 개선 계획·이관 절차·향후 개선·config baking 문서
```

### Key Configuration Files (per environment)
- `main.tf` — 모듈 구성 및 리소스 호출
- `variables.tf` — 변수 정의
- `terraform.tfvars` — 변수 값. **`.gitignore` 대상이다** (시크릿 + 컨테이너 이미지 태그)
- `versions.tf` — Terraform/프로바이더 버전 제약
- `outputs.tf` — 다른 환경에서 참조할 출력값

#### 이미지 태그는 `terraform.tfvars`에 둔다

컨테이너 이미지 태그(`grafana_version`, `monitoring_*_image`)는 `environments/monitoring/terraform.tfvars`에 있다.

⚠️ **이 파일은 `.gitignore`의 `*.tfvars`에 걸려 있어 배포된 이미지 태그가 git 이력에 남지 않는다.**
롤백하려면 이전 태그를 따로 기억해야 하므로, **태그를 바꿀 때 주석으로 이전 값을 남길 것.**
파일 안의 이미지 태그 블록에 그 규칙을 적어 뒀다.

> 2026-08-20 이전에는 추적 가능하도록 `images.auto.tfvars`로 분리하고 `.gitignore`에 예외를
> 뒀었으나, 파일이 둘로 갈리는 것을 피하려고 `terraform.tfvars`로 되돌렸다. 되돌리면서
> `terraform plan`이 **No changes**임을 확인했다.
- 현재 `environments/monitoring/`에만 있다. Prod/Dev의 `spring_app_image`는 제외했다 —
  **CodeDeploy가 실행 중인 태스크 정의를 소유**(`ignore_changes = [task_definition]`)하므로
  tfvars 값이 실제 배포본을 반영하지 않는다 (dev는 `openjdk:17-jdk-slim` 플레이스홀더 상태)

## Network Configuration

- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24 (2a), 10.0.2.0/24 (2c) — ALB, Monitoring EC2
- **Private Subnets**: 10.0.11.0/24 (2a), 10.0.12.0/24 (2c) — Prod/Dev EC2, RDS
- **Availability Zones**: ap-northeast-2a, ap-northeast-2c
- **NAT**: Monitoring 인스턴스(public subnet)가 private subnet의 NAT 역할 수행
- **Source/Dest Check**: Monitoring 인스턴스에서 비활성화 (NAT용)

⚠️ **AZ 배치가 어긋나 있다**: RDS는 **2c**에 있는데 Prod EC2는 **2a**에 있어, 모든 Prod DB 쿼리가 cross-AZ로 나간다.
RDS는 `multi_az = false`이고 db_subnet_group이 2a/2c를 모두 포함해 **AZ가 코드에 고정되어 있지 않다** — 재생성 시 바뀔 수 있다.

## EC2 Instances (ECS Cluster)

단일 ECS 클러스터 `groble-cluster`에 3대의 EC2 인스턴스 (모두 Ubuntu AMI + user_data로 ECS 에이전트 수동 설치):

| Instance | Type | Subnet | Volume | 용도 |
|----------|------|--------|--------|------|
| Production | t3.medium | Private (2a) | 30GB gp3 | Prod API, Redis |
| Development | t3.medium | Private (2c) | 30GB gp3 | Dev API, MySQL, Redis |
| Monitoring | t3.small | Public (2a) | 30GB gp3 | 모니터링 스택 + **NAT + bastion + WireGuard VPN** |

**Monitoring 인스턴스는 4가지 역할을 겸직한다** — 죽으면 관측·아웃바운드·개발자 접근이 동시에 끊긴다.

### 노드 부트스트랩 주의사항 (`modules/platform/ecs-cluster/user_data/`)

- ECS 에이전트가 `amazon/amazon-ecs-agent:latest`로 **버전 고정 없이** 실행된다.
- **credential 프록시용 iptables/sysctl이 재부팅에 영속되지 않는다** (`iptables-persistent` 없음).
  재부팅 시 태스크 IAM 롤이 조용히 깨진다 — 과거 Loki S3 적재 실패의 원인이었다.
- `ECS_RESERVED_MEMORY=64`로 실제 오버헤드(~400-500MB)보다 크게 낮게 잡혀 있다.
- `aws_instance`에 `lifecycle { ignore_changes = [ami] }`(monitoring은 `user_data`도)가 걸려 있어,
  **user_data를 수정해도 실행 중인 노드에 반영되지 않는다.**

## Services

### Spring Boot API (ECS, awsvpc mode)
- Port 8080, Health check: `/actuator/health` (30s interval) — **liveness/readiness 구분 없음**
- **Prod**: CPU 512, `memoryReservation` 500 / `memory` 1500, **desired_count = 1**, Spring Profiles: `prod,common,secret-prod,proxy`
- **Dev**: CPU 512, `memoryReservation` 500 / `memory` 1500, **desired_count = 1**, Spring Profiles: `dev,common,secret-dev,proxy`
- Blue/Green 배포 (CodeDeploy)

> `awsvpc` 모드는 태스크당 ENI 1개를 소비한다. t3 계열은 ENI가 3개(primary 1 + secondary 2)이므로
> **노드당 API 태스크는 최대 2개**다. 밀도를 논할 때 메모리가 아니라 이 제약이 상한이다.

### Database
- **Prod**: RDS MySQL **8.4.11** (**db.t3.micro**, gp2, 암호화, 7일 백업, **20GB→100GB** auto-scaling, **단일 AZ / 2c**)
  > ⚠️ `engine_version`은 **마이너까지 정확히 고정**한다(`"8.4.11"`). `"8.4"`로 두면 AWS가 패밀리
  > 기본값(8.4.9)으로 해석해 다운그레이드를 시도하고 apply가 실패한다.
  > 백업창 `18:00-19:00` UTC = KST 03~04시, 점검창 `sun:19:00-sun:20:00` UTC = KST 월 04~05시.
  > db.t3.micro는 메모리 1GiB다. 용량을 논할 때 EC2의 t3.medium과 혼동하지 말 것 — 이전 문서가 `db.t3.medium` / `100GB→1000GB`로 잘못 적고 있었다.
- **Dev**: MySQL 8.0 컨테이너 (host mode, 256MB, **데이터가 노드 로컬 디스크** `/opt/mysql-dev-data`)

### Redis 7 (ECS, host mode)
- Port 6379, Memory 128MB, Prod/Dev 모두 컨테이너 기반
- 앱은 **노드의 사설 IP로 직접 접속**한다 (`environments/*/main.tf`에서 `data.aws_instance`로 조회)

⚠️ **Redis 내용물의 대부분은 캐시가 아니라 결제 경로의 트랜잭션 상태다** (groble-backend 확인):

| 키 | 용도 | Redis가 유일한 권위 소스인가 |
|---|---|---|
| `checkout:idempotency:*` | 결제 멱등성 키 | **예** |
| `stock:reserved:*` | 재고 예약 카운터 | **예** |
| `checkout:session:*` | 체크아웃 세션 | 예 |
| `active:sessions:*` | 활성 세션 추적 | 예 |
| `email:verification:*`, `password_reset:rate:*` | 인증코드·레이트리밋 | 예 |
| `user:cache:*` | JWT 사용자 캐시 | 아니오 (DB에서 회복) |

**Redis 유실은 "캐시 미스"가 아니라 중복 결제·재고 초과 판매로 이어질 수 있다.** 관련 변경 시 주의할 것.

### Monitoring Stack (모두 host mode networking)

| Service | Image | Port | CPU/Memory |
|---------|-------|------|------------|
| Grafana | **`groble-grafana:11.6.3-*` (ECR, config baked)** | 3000 | 250/256MB |
| Prometheus | **`groble-prometheus:v2.45.0-*` (ECR, config baked)** | 9090 | 512/512MB |
| Loki | **`groble-loki:3.6.15-*` (ECR, config baked)** | 3100 | 512/256MB |
| OpenTelemetry | **`groble-otelcol:0.132.0-*` (ECR, config baked)** | 4317(gRPC), 4318(HTTP) | 256/256MB |
| Node Exporter | prom/node-exporter:latest | 9100 | DAEMON, task memory 128MB |
| cAdvisor | gcr.io/cadvisor/cadvisor:latest | 8081 | DAEMON, task memory 256MB |
| RDS Exporter | prometheuscommunity/mysqld_exporter:latest | 9104 | -/128MB |

**Grafana·Prometheus·Loki·otelcol 전부 `groble-images` CI가 설정을 구워 ECR에 push한 이미지를 쓴다.**
설정 변경은 이 리포지토리가 아니라 `groble-images`에서 하고, `terraform.tfvars`의 이미지 태그를 올린다.

**Grafana도 Phase 2-2에서 config baking 대상이 되었다** (10.2.0 Docker Hub → ECR 11.6.3).
대시보드 3개 · 데이터소스(UID 고정) · **알림 규칙**이 모두 이미지에 있고 `readOnly`로 강제된다.

- 11.x로 올린 이유는 **네이티브 AWS SNS contact point**다. 10.2에는 없어 Slack Webhook을
  새로 발급해야 했고, 그러면 시크릿이 하나 는다. Phase 1의 SNS→Chatbot→Slack 경로를 그대로 재사용했다
- ⚠️ **10.2로의 롤백은 불가능하다** — Grafana 11이 기동 시 SQLite 스키마를 단방향 마이그레이션한다
- ⚠️ **`/opt/grafana/data`의 SQLite는 여전히 노드 로컬이다.** 프로비저닝 대상(대시보드·데이터소스·알림)은
  이미지에서 복원되지만, **사용자 계정 · 알림 silence · UI로 만든 기존 대시보드 4개는 노드 교체 시 유실된다**
- Prometheus **recording rule 12건**에 대시보드와 알림이 의존한다. `http_server_requests_seconds_bucket`은
  17,457 시계열(TSDB의 43%)이라 대시보드에서 `histogram_quantile`을 직접 돌리면
  **Prometheus가 512 MiB 하드리밋에서 OOM으로 죽는다 — 실제로 죽인 적이 있다.**
  `groble:*` recording rule을 담은 이미지를 배포하지 않으면 패널이 비고 알림은 NoData가 된다
- 노드 타깃(node-exporter·cAdvisor) 스크레이프는 **`ec2_sd_config`**로 발견한다
  (`tag:Cluster = groble-cluster` AND `instance-state-name = running`).
  ⚠️ 새 노드에 이 태그가 전파되지 않으면 **경고 없이 스크레이프 목록에서 누락된다**

**모니터링 데이터 흐름:**
```
Applications → OTLP (4317/4318) → OpenTelemetry Collector → Prometheus (metrics) + Loki (logs)
Node Exporter (9100) + cAdvisor (8081) → Prometheus scrape
RDS Exporter (9104) → Prometheus scrape
All → Grafana (3000) Dashboard
```

앱의 OTLP 엔드포인트는 **모니터링 인스턴스의 사설 IP로 하드코딩**되어 있다
(`environments/*/main.tf`의 `otel_exporter_endpoint`).

**스토리지 보존:**
- **Prometheus: 로컬 15일 (10GB)뿐이다.** S3 버킷(`prometheus_storage`)과 IAM 권한이 존재하지만
  **실제로는 사용되지 않는다** — 바닐라 Prometheus는 S3에 직접 쓸 수 없고, Thanos/Mimir 같은 구성요소가 없다.
  노드 교체 시 로컬 데이터도 함께 사라진다.
- Loki: S3 저장 (30일 자동 삭제) — 실제로 동작한다.

### Load Balancing
- **ALB**: Internet-facing, idle timeout 300s
- **Listeners**: HTTPS(443) primary, HTTP(80)→HTTPS redirect, HTTPS(9443) CodeDeploy test
- **Target Groups**: Prod Blue/Green, Dev Blue/Green, Monitoring (총 5개)
- **Domains**: `api.groble.im` (prod), `api.dev.groble.im` (dev), `monitor.groble.im` (monitoring)
- ⚠️ 타깃그룹에 **`deregistration_delay`가 설정되어 있지 않다** (기본 300초).
  ECS `ECS_CONTAINER_STOP_TIMEOUT=30s`와 정렬되지 않아 in-flight 요청이 잘릴 수 있다.

### Blue/Green Deployment (CodeDeploy)
- Deploy Config: `ECSAllAtOnce`
- Test Listener (9443)로 Green 검증 후 트래픽 전환
- Blue 종료 대기: 2분
- 자동 롤백: DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM
- ECS 서비스에 `lifecycle { ignore_changes = [task_definition, load_balancer] }`가 걸려 있다
  (CodeDeploy가 이 둘을 관리하므로 Terraform이 손을 뗀 상태)

## Security

### WAF (AWS WAF v2, ALB 연결)
- **Managed Rules** (Count mode): CommonRuleSet, KnownBadInputs, SQLi, IP Reputation
- **Custom Rules**: IP Rate limit 2000/5min, Global 50000/5min, Login 50/5min, Request size 1MB
- **Geo-blocking**: KR, JP, SG, AU, NZ, HK, TW, TH, VN, MY, PH, ID, IN 허용

### Security Groups (6개)
1. **LB SG**: 80, 443, 9443 from 0.0.0.0/0
2. **Prod Target SG**: 80, 8080, 22, 3306, 6379, 9100, 8081
3. **Dev Target SG**: 80, 8080, 22, 3306, 6379, 9100, 8081
4. **Monitoring SG**: **51820/UDP (WireGuard, `0.0.0.0/0` 개방)**, 22, 3000, 4317/4318, 3100, 9090, NAT(all TCP/UDP)
5. **API Task SG**: 8080 from ALB only (awsvpc 격리)
6. **RDS MySQL SG**: 3306 from **Prod Target · API Task · Monitoring** (SG 참조 3건).
   ⚠️ **Dev Target SG는 없다** — dev는 컨테이너 MySQL을 쓰므로 prod RDS에 붙을 일이 없다.
   ⚠️ **CIDR 인그레스가 하나도 없다** (VPN 서브넷 포함). 아래 접근 경로 참조

**개발자 접근 경로**: WireGuard(51820) → VPN 서브넷 `10.6.0.0/24` → 모니터링 노드 SSH(22) → private 노드.
SSM Session Manager는 아직 도입되지 않았다.

⚠️ **RDS는 VPN에서 직접 닿지 않는다.** VPN이 `10.0.0.0/16`을 라우팅하고 RDS 사설 IP까지 ping도 되지만,
RDS SG에 CIDR 인그레스가 없어 3306이 거부된다. **모니터링 노드를 경유하는 SSH 터널로만 접속된다:**

```bash
ssh -f -N -L 13306:<rds-endpoint>:3306 -i <key>.pem ubuntu@10.0.1.193
```

> 접속 계정 `groble_root`는 `mysql_native_password`를 쓴다. **MySQL 9.x 클라이언트는 이 플러그인을
> 제거해서 접속하지 못한다** (`mysql_native_password.so` 없음). 8.x 클라이언트나 `pymysql`을 쓸 것.

### IAM Roles (`modules/infrastructure/iam-roles/main.tf`)

| 역할 | 실제 부착된 정책 |
|---|---|
| **ECS Instance Role** | `AmazonEC2ContainerServiceforEC2Role`, `AmazonEC2ContainerRegistryReadOnly`, 인라인 `sts:AssumeRole` |
| **ECS Task Execution Role** | `AmazonECSTaskExecutionRolePolicy`, `AmazonEC2ContainerRegistryPowerUser` |
| **ECS Task Role** | `AmazonS3FullAccess`, `AWSKeyManagementServicePowerUser`, `AmazonSSMReadOnlyAccess`, 인라인 KMS 키 사용, 인라인 `ssm:GetParameters`(`parameter/groble/*`), 인라인 `monitoring-loki-s3-access`, 인라인 `monitoring-prometheus-access` |
| **CodeDeploy Service Role** | ECS Blue/Green, ELB 수정 |

⚠️ 주의할 점 두 가지:
- **Task Role에 `ec2:DescribeInstances`가 이미 있다.** 인라인 `monitoring-prometheus-access`에 `ec2:DescribeInstances` / `DescribeAvailabilityZones` / `DescribeRegions`가 포함되어 있다
  (`modules/services/monitoring/prometheus/main.tf`). **Prometheus `ec2_sd_config` 도입 시 IAM 추가 작업은 필요 없다** — 이전 문서가 "권한이 없다"고 잘못 적고 있었다.
- **`ssm:GetParameters`는 Task Role에 있고 Execution Role에는 없다.**
  ECS 태스크 정의의 `secrets`(`valueFrom`) 블록은 **Execution Role** 권한을 쓰므로,
  SSM 기반 시크릿 주입을 도입하려면 Execution Role에 별도로 추가해야 한다.

### Secrets Management
- **KMS**: S3 버킷, RDS 스토리지, 파라미터 암호화
- ⚠️ **비밀값이 태스크 정의에 평문 환경변수로 주입된다.** SSM Parameter Store가 구축되어 있고
  Task Role에 접근 권한도 있지만, 실제로는 쓰이지 않는다:
  ```hcl
  { name = "DB_PASSWORD", value = var.mysql_root_password }   # 평문
  ```
  이 값은 **Terraform state · 태스크 정의 JSON · ECS 콘솔**에 그대로 남는다.
  Grafana `GF_SECURITY_ADMIN_PASSWORD`도 동일하다.

## Important Variables

### Shared Environment
- `project_name` = "groble"
- `vpc_cidr` = "10.0.0.0/16"
- `aws_region` = "ap-northeast-2"
- `key_pair_name` = "groble_prod_ec2_key_pair"
- `ssl_certificate_arn` — ACM 인증서 (HTTPS)

### 하드코딩된 사설 IP (`modules/platform/ecs-cluster/variables.tf`)
```
prod_instance_private_ip       = "10.0.11.62"
dev_instance_private_ip        = "10.0.12.215"
monitoring_instance_private_ip = "10.0.1.193"
```
Redis 호스트·OTLP 엔드포인트·Prometheus 스크레이프 타깃이 이 IP들에 의존한다.

### Environment-Specific
- **Dev**: `environment = "dev"`, `mysql_database = "groble_develop_database"`
- **Prod**: `environment = "prod"`, `mysql_database = "groble_prod_database"`

### ECR Lifecycle
- **Prod**: 최근 10개 이미지 유지, 태그 prefix: v, release, prod
- **Dev**: 최근 5개 이미지 유지, 태그 prefix: v, dev, feature, main

## Development Workflow

1. **배포 전**: AWS 프로필, 키페어, SSL 인증서 확인
   (state는 S3 versioning으로 이력이 남으므로 수동 백업은 더 이상 필요하지 않다)
2. **변경 순서**: 항상 shared → monitoring → dev → prod 순서
3. **shared 변경**: 모든 환경에 영향, 신중하게 계획
4. **모듈 변경**: 여러 환경에 영향, 충분히 테스트
5. **CloudWatch 로그 비활성화**: Loki로 대체하여 비용 절감
6. **모니터링 설정 변경**: 이 리포지토리가 아니라 `groble-images`에서 (Prometheus/Loki/otelcol)
7. **인프라 구조 변경 전**: `docs/infra-ha-improvement-plan.md`와 충돌하지 않는지 확인

## Prerequisites

- **Terraform >= 1.10** (`use_lockfile` 요건). `.terraform-version`이 1.15.8을 고정하므로 tfenv 사용을 권장한다
  > homebrew-core의 `terraform` 포뮬러는 BUSL 전환 시점인 1.5.7에서 갱신이 멈춰 있다. `brew upgrade`로는 올라가지 않는다
- AWS CLI (`groble-terraform` 프로필 설정)
- 키페어 `groble_prod_ec2_key_pair` (ap-northeast-2)
- ACM SSL 인증서

## Common Issues

- **Dependency errors**: shared 환경이 먼저 배포되었는지 확인
- **Key pair errors**: ap-northeast-2 리전에 키페어 존재 확인
- **SSL certificate errors**: ACM 인증서 상태 확인
- **AWS auth errors**: AWS 프로필 설정 확인
- **NAT 문제**: Monitoring 인스턴스의 Source/Dest Check 비활성화 확인
- **서비스 미등록**: EC2 User Data의 ECS 클러스터 등록 스크립트 확인
- **태스크가 AWS API 호출에 실패**: 노드 재부팅으로 credential 프록시 iptables가 사라졌을 가능성.
  `iptables -t nat -L` 로 `169.254.170.2` DNAT 규칙 존재 확인
- **태스크가 배치되지 않음(RESOURCE:ENI)**: 노드당 awsvpc 태스크 2개가 상한. 노드를 늘리거나 desired를 줄일 것
- **`Error acquiring the state lock`**: 다른 곳에서 Terraform이 실행 중이다. 프로세스가 비정상 종료해 잠금이 남았다면
  에러에 표시된 Lock ID로 `terraform force-unlock <ID>` — **실행 중인 작업이 없음을 확인한 뒤에만** 쓸 것
- **backend 인증 실패**: `backend.tf`에 `profile`이 있는지 확인. **backend는 provider 설정을 상속하지 않는다**
- **state 객체가 SSE-S3(AES256)로 저장됨**: `backend.tf`에서 `kms_key_id`가 빠졌다. 생략하면 backend가 AES256 헤더를
  보내 버킷 기본 암호화(SSE-KMS)를 덮어쓴다
