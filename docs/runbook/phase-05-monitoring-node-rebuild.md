# Phase 5 — 모니터링 노드 재구축

> [← Phase 4](./phase-04-deployment-controller.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 6 →](./phase-06-elasticache.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | 현재 모니터링 노드는 public 2a에 있고 NAT·bastion·VPN을 겸직한다. private 2c의 AL2023 노드로 옮긴다 |
| **사용자 영향** | 없음 — 구 노드를 병존시킨 채 전환한다 |
| **되돌리기** | DNS 레코드 되돌리기 (재배포 없음) |

> 모니터링 노드는 계획서 §0에 따라 **pet으로 유지**한다. ASG로 만들지 않는다.

---

## 절차

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

## 검증

- [ ] Grafana 대시보드가 신 노드에서 정상 (프로비저닝 복원 확인)
- [ ] Prometheus 타깃이 `ec2_sd`로 전부 잡히는지
- [ ] 5-b 후 앱 로그·트레이스가 **여전히 구 노드**로 들어오는지 (간접화 자체의 검증)
- [ ] 5-d 후 60초 내 앱 트레이스·로그가 **신 otelcol**로 들어오는지 (Loki에 신규 로그 유입 확인) — 재배포 없이 옮겨졌는지가 핵심
- [ ] SSM으로 신 노드 접속 가능

## 롤백

DNS 레코드를 구 노드 IP로 되돌린다 (재배포 없음). 구 노드의 스택을 재기동.

---

[← Phase 4 — 배포 컨트롤러 전환](./phase-04-deployment-controller.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 6 — Prod Redis → ElastiCache →](./phase-06-elasticache.md)
