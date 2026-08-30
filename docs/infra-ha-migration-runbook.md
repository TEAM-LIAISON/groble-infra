# 인프라 이관 실행 절차 (Migration Runbook)

> [`infra-ha-improvement-plan.md`](./infra-ha-improvement-plan.md)에서 확정한 To-Be 구조로
> **현재 운영 중인 인프라를 안전하게 옮기는 순서와 절차.**
>
> 설계의 "무엇을·왜"는 계획서에, 실행의 "어떤 순서로·어떻게 되돌리는가"는 이 문서에 있다.
>
> **각 Phase의 상세 절차는 [`runbook/`](./runbook/) 아래 개별 문서에 있다.** 이 문서는 목차·공통 원칙·부록이다.
>
> 아래 **전체 순서 요약 표가 진행 상태의 단일 진실이다.** 상태가 바뀌면 이 표와 해당 Phase 문서의
> 헤더를 함께 고친다 (문서 규칙은 [`docs/README.md`](./README.md)).

---

## 이 문서의 원칙

1. **한 번에 한 가지만 바꾼다.** 문제가 생겼을 때 원인이 명확해야 한다.
2. **모든 단계에 되돌리기 지점이 있다.** 되돌릴 수 없는 단계는 그 사실을 명시하고, 사전 검증을 더 무겁게 한다.
3. **사용자 영향이 없는 단계를 앞에 둔다.** 위험한 단계에 도달했을 때는 이미 안전망(알람·관측·state 백업)이 갖춰져 있어야 한다.
4. **각 단계는 독립적으로 중단 가능하다.** 도중에 멈춰도 인프라가 일관된 상태로 남아야 한다.

---

## 전체 순서 요약

| Phase | 내용 | 상태 | 사용자 영향 | 되돌리기 |
|---|---|---|---|---|
| **[0](./runbook/phase-00-terraform-state-s3.md)** | Terraform state → S3 backend + 잠금 | ✅ 완료 (2026-08-16) | 없음 | 로컬 state 복원 |
| **[1](./runbook/phase-01-alarm-backstop.md)** | CloudWatch 알람 백스톱 + SNS 외부 알림 | ✅ 완료 (2026-08-17) | 없음 | 리소스 삭제 |
| **[2](./runbook/phase-02-observability.md)** | Prometheus `ec2_sd` 전환 + Grafana as-code | 🔄 진행 중 — 배포·검증 완료, **백엔드 회신 대기 2건** | 없음 | 이전 이미지 태그로 롤백 |
| **[3](./runbook/phase-03-nat-gateway.md)** | NAT Gateway + S3 Gateway Endpoint, 라우트 전환 | 🔄 진행 중 — 3-a(IP 확보) 완료, **외부 업체 허용목록 등록 대기** | 진행 중이던 아웃바운드 연결 단절 | 스위치 되돌리기 (CLI 한 줄) |
| **[4](./runbook/phase-04-monitoring-node-rebuild.md)** | 모니터링 노드 재구축 (private 2c, AL2023) + OTLP DNS 간접화 | ⬜ 미착수 — **다음 작업** | 없음 (구 노드 병존). 관측만 수 분 중단 | DNS 레코드 되돌리기 (재배포 없음) |
| **[5](./runbook/phase-05-deployment-controller.md)** | 배포 컨트롤러 CodeDeploy → ECS rolling | ⬜ 미착수 — **앱 측 차단 조건 4건 대기** | 없음 (리스너 스왑) | **리스너 규칙 되돌리기** |
| **[6](./runbook/phase-06-elasticache.md)** | Prod Redis → ElastiCache (**stop-first**, rolling 아님) | ⬜ 미착수 | **진행 중 결제 세션 소실 + 1~2분 순단** ⚠️ | 되돌려도 재소실 |
| **[7](./runbook/phase-07-prod-asg.md)** | Prod ASG 전환 (구 노드 드레인) | ⬜ 미착수 | 없음 | 구 노드 재활성화 |
| **[8](./runbook/phase-08-dev-migration.md)** | Dev 전환 (RDS + ElastiCache + ASG) | ⬜ 미착수 | Dev만 | 단계별 |
| **[9](./runbook/phase-09-access-path.md)** | 접근 경로 정리 (WireGuard/bastion/22 폐기) | ⬜ 미착수 | 없음 | SG 규칙 복원 |
| **[10](./runbook/phase-10-secrets-ssm.md)** | Secrets → SSM Parameter Store | ⬜ 미착수 | 없음 (rolling 재배포) | 이전 태스크 정의 |
| **[11](./runbook/phase-11-cleanup.md)** | 잔재 정리 및 문서 갱신 | ⬜ 미착수 | 없음 | — |
| **[별건](./runbook/adhoc/rds-mysql-84-upgrade.md)** | RDS MySQL 8.0 → 8.4 (확장 지원 과금 $178.56/월 중단) | 📦 **종결** (2026-08-29) — 전환·정리 완료 | 쓰기 차단 35초 + **앱 재연결 문제로 7~8분 쓰기 실패** | 되돌릴 수 없음 (최종 스냅샷만 보유) |

**RDS 8.4 업그레이드는 Phase 순서와 독립적이다.** 2026-08-01 부터 확장 지원 과금이 자동으로 붙기
시작해 촉발된 별건이며, Phase 6·7 과 자원이 겹치지 않아 언제든 끼워 넣을 수 있다.

**Phase 6 이전까지는 사용자 영향이 사실상 0이다.** 그 지점까지 최대한 검증을 쌓고 진입한다.

### 4↔5 를 맞바꾼 이유 (2026-08-30)

**원래 Phase 4 가 배포 컨트롤러 전환, Phase 5 가 모니터링 노드 재구축이었다.** 배포 컨트롤러 전환이
앱 측 차단 조건 4건(계획서 §3)에 막혀 회신을 기다리는 동안 모니터링 노드 재구축은 진행할 수 있어,
문서상의 번호를 맞바꿨다.

- **둘 사이에 의존이 없다.** 모니터링 노드 재구축의 OTLP 재배포는 CodeDeploy Blue/Green 으로 해도 무방하다
- **Phase 3 미완(모니터링 노드가 여전히 NAT)이어도 안전하다.** 이 Phase 는 NAT/bastion/WireGuard 를
  건드리지 않는다 — 드레이닝은 ECS 태스크 배치만 바꾸고 호스트 역할은 그대로다
- **오히려 먼저 하는 편이 낫다.** 관측 스택을 빼내면 전 private 서브넷의 egress 가 걸린
  NAT 노드가 가벼워진다 (Prometheus 는 512 MiB 하드리밋에서 OOM 으로 죽은 전력이 있다)
- **6·7 은 앞당기지 않는다.** Phase 7 은 Phase 6(Redis 외부화)에 묶여 있고, Phase 6 은 이 마이그레이션에서
  유일하게 사용자 영향이 실재하는 단계다. 무영향 작업을 다 하기 전에 그것부터 감수할 이유가 없다

> 번호를 바꿨을 뿐 **각 Phase 의 내용·차단 조건·되돌리기는 그대로다.** 이 날 이전에 작성된
> 문서·PR·백엔드 요청서에는 옛 번호가 남아 있을 수 있다.

### 지금 무엇에 막혀 있나

**진행 중인 3건이 모두 백엔드 회신을 기다린다.** 무엇을 물어놨고 무엇이 돌아왔는지는
[`handoff/README.md`](./handoff/README.md)에 모여 있다.

| 대기 | 막고 있는 것 |
|---|---|
| [egress IP 허용목록](./handoff/egress-ip-allowlist.md) | **Phase 3 착수 조건** |
| [JVM DNS 캐시 TTL](./handoff/rolling-deploy-prerequisites.md) (§3, 문항 9·10) | **Phase 4 F단계 조건.** 무기한이면 OTLP 간접화가 무의미해진다. A~E 는 막지 않는다 |
| 계획서 §3 앱 측 차단 조건 **A~D** (expand/contract · readiness/liveness · graceful shutdown · 드레이닝 값) | **Phase 5 착수 조건.** 요청서 [rolling-deploy-prerequisites.md](./handoff/rolling-deploy-prerequisites.md) §2 |
| [결제 지표 3종 노출](./handoff/payment-alerts-review.md) (§6) | 알림 R10~R14. Phase 2 완료는 막지 않는다 |
| 전환 구간(02:19~02:27) 결제 점검 · 첫 09:00 배치 확인 | [RDS 8.4 업그레이드](./runbook/adhoc/rds-mysql-84-upgrade.md) — 전환은 끝났고 사후 확인만 남았다 |

---

## 착수 전 체크리스트

- [ ] `terraform version` ≥ 1.10 (Phase 0의 S3 네이티브 잠금 요건)
- [ ] `aws sts get-caller-identity --profile groble-terraform` 정상 (SSO 토큰 유효)
- [ ] 현재 state 파일 4개를 **작업 외부(로컬 백업 디렉터리)에 복사해 둔다**
- [ ] `terraform plan`이 모든 환경에서 **no changes**로 깨끗한지 확인 — drift가 있으면 먼저 해소
- [ ] 계획서 §3 "rolling 전환의 차단 조건 — 앱 측 작업" **4건**(expand/contract 합의 · readiness/liveness 분리 · graceful shutdown · 드레이닝 값 정렬)이 groble-backend에서 완료되었는지 — **Phase 5의 차단 조건**. Phase 0~4는 이와 무관하게 먼저 진행할 수 있다
- [ ] **WireGuard 51820 소스를 `0.0.0.0/0` → 팀 IP로 축소** (계획서 §2.5 선행 즉시 조치 — Phase 9까지 6~8주를 열어둘 이유가 없다)
- [ ] 저트래픽 시간대 확인 (Phase 3·6에 필요)
- [ ] **외부 업체 허용목록에 새 egress IP 등록 완료** — [Phase 3](./runbook/phase-03-nat-gateway.md) 전환의 차단 조건.
  등록 전에 전환하면 짧은 블립이 아니라 **등록될 때까지 지속되는 장애**가 된다
  ([질의서](./handoff/egress-ip-allowlist.md))
- [ ] 롤백 판단자와 연락 체계 합의

### 중단(Abort) 기준

아래 중 하나라도 해당하면 **즉시 해당 Phase를 롤백하고 원인 분석 후 재개**한다.

- ALB 5xx가 기준선 대비 유의미하게 상승
- 타깃그룹 `UnHealthyHostCount` > 0이 5분 이상 지속
- ECS 서비스가 desired count를 10분 이상 충족하지 못함
- Terraform apply가 예상하지 못한 리소스 **삭제/재생성**을 계획에 포함 (plan을 반드시 육안 확인)

---

## 부록 A — Phase별 예상 소요와 권장 간격

| Phase | 작업 시간 | 다음 Phase까지 관찰 |
|---|---|---|
| 0 | 반나절 | — |
| 1 | 반나절 | **없음** — 기준선은 CloudWatch 보관 데이터로 즉시 확보 가능하다 (실제로 그렇게 했다) |
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

**전체 약 6~8주.** Phase 5·6·7 뒤의 관찰 기간을 줄이지 않는 것을 권한다 — 문제가 즉시 드러나지 않는 종류의 변경들이다.

---

## 부록 B — 각 Phase의 "되돌릴 수 없는 지점"

| Phase | 되돌릴 수 없게 되는 시점 | 그 전에 반드시 확인할 것 |
|---|---|---|
| [4](./runbook/phase-05-deployment-controller.md) | 구 CodeDeploy 서비스 제거 | rolling 배포 1회 이상 성공, 서킷 브레이커 동작 |
| [6](./runbook/phase-06-elasticache.md) | ElastiCache로 전환한 순간 | 저트래픽 시간대인지, 결제 지표 기준선 기록 |
| [7](./runbook/phase-07-prod-asg.md) | 구 Prod 인스턴스 종료 | 신 노드에서 태스크 정상 기동, Prometheus 타깃 등록, SSM 접속. **+ JVM 힙 상한 수정 완료** — 신 노드엔 스왑이 없어 미수정 시 prod API가 OOM으로 죽는다 ([Phase 2-0](./runbook/phase-02-observability.md)) |
| [8](./runbook/phase-08-dev-migration.md) | 구 Dev MySQL 컨테이너 제거 | RDS로 데이터 복원 완료 및 검증 |
| [9](./runbook/phase-09-access-path.md) | 구 VPN 노드 종료 | **팀 전원의 SSM 전환 완료** |

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
