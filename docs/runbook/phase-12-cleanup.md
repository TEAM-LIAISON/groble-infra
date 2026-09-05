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

## 문서 트리 정리 — 이 Phase 가 문서의 성격을 바꾼다

이 Phase 를 끝내는 순간 **`phase-00` ~ `phase-12` 는 닫힌 집합**이 되고,
`runbook/` 은 "따라 할 절차"에서 **"왜 이렇게 생겼는지의 기록"** 으로 바뀐다.
앞으로 생기는 실행 문서는 전부 [`adhoc/`](./adhoc/) 으로 간다.
근거와 전체 그림은 [`docs/README.md` — 마이그레이션이 끝나면](../README.md#마이그레이션이-끝나면--문서는-어떻게-되나) 에 있다.

**아무 문서도 삭제하지 않는다.** 아래는 전부 "표시와 색인을 붙이는" 작업이다.

- [ ] **[runbook/README.md](README.md) 상단에 「앞으로도 쓰는 절차」 색인 신설**
      각 Phase 문서의 `## ✅ 완료 요약` 안에 둔 **"재사용할 절차"** 항목을 모은다.
      최소 2건이 확정돼 있다 — [Phase 4](./phase-04-monitoring-node-rebuild.md) 의 **E·F**(모니터링 노드 교체:
      레코드 변경 → 구 노드 수신 중단, 앱 재배포 없음) · [Phase 9](./phase-09-prod-asg.md) 의 **instance refresh**.
      나머지 Phase 는 기록으로 가라앉는다
- [ ] **[runbook/README.md](README.md) 헤더에 성격 재선언** — "이관 실행 절차"에서
      "완료된 이관의 기록 + 반복 사용하는 절차의 색인"으로. 순서 요약 표는 전 Phase ✅ 로 마감한다
- [ ] **[계획서](../plan/infra-ha-improvement-plan.md) 헤더에 `✅ 실현됨 (Phase 12, 날짜)` 표시**
      내용은 `CLAUDE.md` 로 흡수되지만 문서는 **결정 근거**로 남는다 —
      "왜 Mac Mini 를 폐기했나 · 왜 단일 AZ 를 유지했나 · 왜 ElastiCache 를 `replication_group` 으로 만들었나"는
      `CLAUDE.md` 가 As-Is 만 담는 규칙이라 거기 들어가지 않는다
- [ ] **[future-improvements](../plan/infra-future-improvements.md) 를 백로그 주 문서로 승격** —
      헤더에 "이제 여기서부터 다음 작업이 나온다"를 명시. 항목을 착수하면 `adhoc/` 에 런북을 만든다
- [ ] **분기 점검을 누가 언제 도는지 정한다** — `CLAUDE.md` 와 완료 문서의 서술이 실제 배포 상태와
      어긋나는지. 어긋난 것은 지우지 말고 무효 표시를 단다
- [ ] **링크·앵커 전수 검사** — [`docs/README.md`](../README.md#문서를-고칠-때) 의 스크립트

---

[← Phase 11 — Secrets를 SSM Parameter Store로](./phase-11-secrets-ssm.md) · [이관 절차 목차](README.md)
