# Phase 3 — NAT Gateway 전환

> [← Phase 2](./phase-02-observability.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 4 →](./phase-04-deployment-controller.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | 모니터링 노드의 NAT 겸직을 제거한다. 되돌리기가 쉬워 초기에 배치했다 |
| **사용자 영향** | 라우트 교체 순간 **기존 연결이 끊긴다**(짧음). ECR pull 중이면 배포가 실패할 수 있다 |
| **시점** | 저트래픽 시간대, **배포가 없는 시간대** |
| **되돌리기** | 라우트 되돌리기 |

---

## 절차

1. NAT Gateway 생성 — **2c public subnet** (`10.0.2.0/24`), EIP 할당
2. **S3 Gateway Endpoint 생성** (무료) — private route table에 연결
3. private route table의 `0.0.0.0/0`을 **NAT 인스턴스 ENI → NAT Gateway**로 변경
   - Terraform: `aws_route.private_nat_route`의 `network_interface_id` → `nat_gateway_id`
4. 모니터링 노드의 `source_dest_check`와 iptables MASQUERADE는 **아직 건드리지 않는다** (롤백 여지 유지)

## 검증

- [ ] private 노드에서 외부 도달 확인: `curl -I https://api.ecr.ap-northeast-2.amazonaws.com`
- [ ] ECR pull 정상 동작 (테스트 배포 1회)
- [ ] SSM/S3 접근 정상
- [ ] NAT Gateway CloudWatch 지표에 트래픽이 잡히는지

## 롤백

라우트를 NAT 인스턴스 ENI로 되돌린다. 모니터링 노드의 NAT 설정을 그대로 두었으므로 즉시 복구된다.

---

[← Phase 2 — 관측 선행 전환](./phase-02-observability.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 4 — 배포 컨트롤러 전환 →](./phase-04-deployment-controller.md)
