# Phase 12 — 잔재 정리 및 문서 갱신

> [← Phase 11](./phase-11-secrets-ssm.md) · [이관 절차 목차](README.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **사용자 영향** | 없음 |
| **되돌리기** | — |

---

## 정리 대상

- [ ] CodeDeploy 애플리케이션 / 배포그룹 / IAM 역할 ([Phase 6](./phase-06-deployment-controller.md)에서 남겼다면)
- [ ] **테스트 리스너(9443)** 및 관련 SG 규칙 — rolling에서는 사용하지 않음
- [ ] 사용하지 않는 Blue 타깃그룹
- [ ] `ecs-cluster` 모듈의 고정 사설 IP 변수 (`prod_instance_private_ip` 등)
- [ ] Ubuntu 기반 user_data 스크립트 3개
- [ ] `/opt/mysql-prod-data` 생성 로직 (fallback MySQL 잔재)
- [ ] 모니터링 노드의 NAT iptables·`source_dest_check` 설정

## 문서 갱신

- [ ] **CLAUDE.md 정정**
  - "ECS Task Role: EC2 describe" → 실제 정책과 불일치 (S3/KMS/SSM + 신규 `ec2:DescribeInstances`)
  - "Prometheus: S3 장기 저장(90일)" → **실제로 미사용**. 현재는 로컬 15일이 전부
  - EC2 인스턴스 표, 배포 전략, 네트워크 구성, Secrets 관리 전면 갱신
- [ ] 계획서 §4의 남은 To-Do 상태 갱신
- [ ] [Phase 9](./phase-09-prod-asg.md)에서 실측한 **노드 복구 시간**을 계획서 §2.1에 반영

---

[← Phase 11 — Secrets를 SSM Parameter Store로](./phase-11-secrets-ssm.md) · [이관 절차 목차](README.md)
