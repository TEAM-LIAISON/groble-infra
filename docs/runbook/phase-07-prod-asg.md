# Phase 7 — Prod ASG 전환

> [← Phase 6](./phase-06-elasticache.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 8 →](./phase-08-dev-migration.md)

| | |
|---|---|
| **상태** | 미착수 |
| **목적** | 이 프로젝트의 본 목표. 무중단 하드웨어 교체가 가능한 구조로 전환한다 |
| **사용자 영향** | 없음 — 신 노드를 먼저 띄우고 구 노드를 드레인한다 |
| **선행 조건** | [Phase 2](./phase-02-observability.md)(관측), [Phase 6](./phase-06-elasticache.md)(Redis 외부화) 완료 + **아래 차단 조건 2건** |
| **되돌리기** | 구 노드 재활성화 |

---

## ⚠️ Phase 2에서 이관된 차단 조건

[Phase 2-0 측정](./phase-02-observability.md#2-0-api-태스크-워킹셋-측정-선행--phase-1에서-이관--완료)에서 드러난 것으로,
**둘 다 이 Phase를 시작하기 전에 해소되어야 한다.**

### 1. JVM 힙 상한 수정 — 안 고치면 신 노드에서 prod API가 OOM으로 죽는다

현재 prod API의 JVM은 `-XX:MaxRAMPercentage=75.0`을 **호스트 RAM(3,837 MiB)** 기준으로 적용해
힙 상한을 **2,878 MiB**로 잡고 있다. 컨테이너 하드리밋은 1,500 MiB다.
초과분은 **현재 노드 `user_data`가 만드는 1 GiB 스왑파일**이 흡수하고 있다 (최대 947 MiB 사용).

> **이 Phase에서 노드가 AL2023 + Launch Template으로 교체되면 그 스왑파일이 사라진다.**
> JVM 설정을 그대로 둔 채 진행하면 신 노드에서 prod API가 OOM kill로 종료된다.

- 요청서: [`docs/handoff/backend-jvm-heap-limit.md`](../handoff/backend-jvm-heap-limit.md)
- [ ] 백엔드 Dockerfile 수정(`-Xms512m -Xmx900m`) 배포 완료
- [ ] 배포 후 2~3일 재측정 → 아래 5번 `memory_reservation` 확정

### 2. `spring-apps` 스크레이프를 태스크 단위로 — `desired_count` 2 이상의 전제

API 태스크는 `awsvpc` 모드라 태스크마다 별도 ENI를 갖는데, Prometheus의 해당 잡은
공개 ALB(`api.groble.im:443`)를 경유한다. **태스크가 2개 이상이 되면 ALB 라운드로빈 때문에
서로 다른 태스크의 카운터가 한 시계열에 섞여 `rate()`가 에러 없이 틀린 값을 낸다.**
`ec2_sd`로는 해결되지 않는다 (인스턴스는 발견해도 태스크 ENI는 발견하지 못함).

- [ ] ECS Service Discovery(Cloud Map) 등록 + Prometheus `dns_sd_configs`(type A) 전환

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

     ⚠️ **위 3개로는 부족하다. Phase 2-1의 relabel 매핑과 대조할 것:**
     - **`Name` 태그가 빠져 있다.** Prometheus가 `Name` → `instance_name` 라벨로 승격하므로,
       빠지면 **신 노드의 `instance_name` 라벨이 비어** 대시보드에서 노드를 구분할 수 없게 된다.
       ASG는 `Name`을 자동으로 붙이지 않는다 — 명시적으로 추가해야 한다
     - **`Type` 값이 기존 노드와 다르다.** 현재 운영 인스턴스는 `Type = "Production"`인데 위 계획은 `"api"`다.
       `node_type` 라벨이 신·구 노드 간에 갈리므로, 값을 통일하거나 **의도한 차이임을 문서화**할 것
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
