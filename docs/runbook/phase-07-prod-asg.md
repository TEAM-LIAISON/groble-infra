# Phase 7 — Prod ASG 전환

> [← Phase 6](./phase-06-elasticache.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 8 →](./phase-08-dev-migration.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | 이 프로젝트의 본 목표. 무중단 하드웨어 교체가 가능한 구조로 전환한다 |
| **사용자 영향** | 없음 — 신 노드를 먼저 띄우고 구 노드를 드레인한다 |
| **선행 조건** | [Phase 2](./phase-02-observability.md)(관측), [Phase 6](./phase-06-elasticache.md)(Redis 외부화) 완료 |
| **되돌리기** | 구 노드 재활성화 |

---

## 절차

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

## 검증

- [ ] **instance refresh 중 5xx가 0인지** — 이 프로젝트의 목표가 달성되었는지 확인하는 핵심 검증
- [ ] 드레이닝 시 in-flight 요청이 끊기지 않는지
- [ ] 노드 1대를 강제 종료했을 때 ASG가 자동 복구하는지, 태스크가 재배치되는지
- [ ] **복구 소요 시간 측정** — 종료 시각 → EC2 unhealthy 감지 → 신 인스턴스 기동 → ECS 등록 → 태스크 RUNNING 각 구간을 기록. 계획서 §2.1의 "실측 전 추정 3~5분+"를 이 값으로 갱신 (To-Do 10). 감지 구간이 길면 ASG 헬스체크 유예/EC2 상태 검사 설정을 조정할 근거가 된다
- [ ] launch type 서비스의 태스크가 DRAINING으로 정상 이동하는지 (3번에서 CP 전략 부착을 미룬 경우 이것이 무중단 교체의 근거)

## 롤백

구 노드를 `ACTIVE`로 되돌리고 ASG `desired = 0`. 구 인스턴스를 제거하기 전(8번)까지는 완전히 되돌릴 수 있다.
**8번 이후는 되돌리기가 어려워진다** — 이 지점을 넘기 전에 4~7번 검증을 충분히 한다.

> 되돌릴 수 없게 되는 시점: **구 Prod 인스턴스 종료.** 그 전에 신 노드에서 태스크 정상 기동, Prometheus 타깃 등록, SSM 접속을 확인한다.

---

[← Phase 6 — Prod Redis → ElastiCache](./phase-06-elasticache.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 8 — Dev 전환 →](./phase-08-dev-migration.md)
