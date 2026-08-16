# Phase 9 — 접근 경로 정리

> [← Phase 8](./phase-08-dev-migration.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 10 →](./phase-10-secrets-ssm.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | bastion·WireGuard·SSH를 폐기하고 SSM으로 일원화한다 |
| **사용자 영향** | 없음 (개발자 워크플로는 변경됨) |
| **선행 조건** | [Phase 5](./phase-05-monitoring-node-rebuild.md)·[7](./phase-07-prod-asg.md)·[8](./phase-08-dev-migration.md)에서 **SSM 접속이 실제로 검증되어 있어야 한다** |
| **되돌리기** | SG 규칙 복원 |

---

## 절차

1. **팀 전환 안내 및 준비**
   - 각자 AWS CLI + Session Manager Plugin 설치
   - IAM 권한 부여 (`ssm:StartSession` 등)
   - 자주 쓰는 포트 포워딩 스크립트 배포 (`scripts/connect-rds-prod.sh`, `connect-rds-dev.sh`)
     — `scripts/`는 현재 리포지토리에 없다(계층 구조 전환 후 죽어 있던 `deploy-step.sh`와 함께 삭제). 이 단계에서 새로 만든다
2. **전환 기간 운영** (1~2주) — WireGuard와 SSM을 병행하며 팀이 SSM에 적응
3. **구 모니터링/NAT/VPN 노드 종료**
4. **SG 정리**
   - 22번 규칙 3곳 제거
   - WireGuard UDP 51820 제거 (현재 `0.0.0.0/0` 개방)
   - `trusted_ips` 변수 폐기
5. **키페어 의존 제거** — launch template에서 `key_name` 제외 (Phase 7에서 이미 제외했다면 확인만)
6. **SSM 세션 로그를 S3/CloudWatch로 설정** (접근 감사 기록)

## 검증

- [ ] 팀 전원이 SSM으로 노드 접속 가능
- [ ] RDS 포트 포워딩으로 DB 클라이언트 연결 가능
- [ ] 세션 로그가 실제로 남는지
- [ ] 22번·51820이 어디에도 열려 있지 않은지 (`aws ec2 describe-security-groups`로 확인)

## 롤백

SG 규칙 복원. 단 구 VPN 노드를 종료한 뒤라면 재구축이 필요하므로, **3번(노드 종료) 전에 팀 전환을 확실히 끝낸다.**

> 되돌릴 수 없게 되는 시점: **구 VPN 노드 종료.** 그 전에 **팀 전원의 SSM 전환 완료**를 확인한다.

---

[← Phase 8 — Dev 전환](./phase-08-dev-migration.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 10 — Secrets를 SSM Parameter Store로 →](./phase-10-secrets-ssm.md)
