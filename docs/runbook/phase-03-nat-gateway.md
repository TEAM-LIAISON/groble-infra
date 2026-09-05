# Phase 3 — NAT Gateway 전환

> [← Phase 2](./phase-02-observability.md) · [이관 절차 목차](README.md) · [다음: Phase 4 →](./phase-04-monitoring-node-rebuild.md)

| | |
|---|---|
| **상태** | 🔄 **진행 중** — 3-a(IP 확보) 완료, **3-b(외부 업체 등록) 대기 중** |
| **목적** | 모니터링 노드의 NAT 겸직을 제거한다. 되돌리기가 쉬워 초기에 배치했다 |
| **사용자 영향** | 경로 교체 순간 **진행 중이던 아웃바운드 연결이 전부 끊긴다**. 인바운드(ALB→태스크)와 VPC 내부 통신은 영향 없다 |
| **시점** | 저트래픽 시간대, **배포가 없는 시간대**. ~~RDS 8.4 전환 이후~~ → **[2026-08-29 종결](./adhoc/rds-mysql-84-upgrade.md)되어 해소됨** |
| **되돌리기** | 스위치 되돌리기 (급하면 CLI 한 줄) |
| **작업 브랜치** | 3-a·3-b 는 **main 에 머지됨**([PR #11](https://github.com/TEAM-LIAISON/groble-infra/pull/11)). 3-c·3-d 는 **main 에서 새 브랜치를 따서** 진행한다 |

---

## 🔖 이어받기 (2026-08-29 기준)

**3-a 까지 끝났다. 다음에 할 일은 3-b 의 회신을 기다리는 것뿐이다.**

- ✅ 선행 조건이던 **RDS 8.4 전환이 2026-08-29 종결**되어, 이제 3-d 를 막는 것은 3-b 하나다
- 여기까지가 **main 에 머지되어 있다.** 이어서 할 때는 **main 에서 새 브랜치를 딴다** —
  전환 스위치가 전부 off 라 머지해도 트래픽이 바뀌지 않으므로, 장수 브랜치를 들고
  역머지하는 부담을 지지 않기로 했다 (2026-08-30 결정)

- EIP `15.165.223.110` 을 확보했다. **미부착 상태라 이 IP 로 나가는 트래픽은 아직 없다**
- S3 Gateway Endpoint `vpce-0db4b7f990ea3d315` 를 만들었다. **라우트 테이블에 연결하지 않았으므로 무해하다**
- private 기본 경로는 여전히 모니터링 노드 ENI(`eni-0bbe59a160c2985ad`)를 가리킨다
- 등록 완료 회신이 오면 **3-c → 3-d 를 순서대로** 진행한다. 남은 것은 스위치 세 개다

---

## 이 Phase 가 4단계인 이유

원래 계획은 "만들고 라우트 바꾸기" 2단계였다. 확인 과정에서 **외부 업체가 우리 출발지 IP 를
허용목록으로 관리한다**는 사실이 나왔고, 이것이 순서를 바꿨다.

**등록되지 않은 IP 로 나가기 시작하면 그 순간부터 차단된다.** 짧은 블립이 아니라 등록될
때까지 지속되는 장애다. 그래서 **IP 를 먼저 확보해 등록을 마친 뒤에** 전환한다.

| 단계 | 무엇 | 트래픽 영향 | 되돌리기 |
|---|---|---|---|
| **3-a** | EIP + S3 엔드포인트 **생성만** | **없음** | 리소스 삭제 |
| **3-b** | 외부 업체 허용목록 **등록** | 없음 (우리 인프라 무변경) | — |
| **3-c** | NAT Gateway **생성만** | **없음** | 리소스 삭제 |
| **3-d** | 경로 **전환** | **있음** ⚠️ | 스위치 되돌리기 |

3-a·3-c 를 굳이 나눈 이유는 **NAT Gateway 는 시간당 요금이 붙고 EIP 는 거의 안 붙기** 때문이다.
등록에 며칠이 걸려도 EIP 만 들고 기다리면 월 $3.6 이다.

---

## 3-a. IP 확보 — ✅ 완료 (2026-08-28)

`create_nat_gateway = false` 인 상태로 apply 했다. **2 to add, 0 to change, 0 to destroy.**

| 리소스 | 값 | 상태 |
|---|---|---|
| EIP | `15.165.223.110` (`eipalloc-07da2e3218f124194`) | 미부착 |
| S3 Gateway Endpoint | `vpce-0db4b7f990ea3d315` | available, **라우트 테이블 미연결** |

**IP 를 만드는 것은 NAT Gateway 가 아니라 EIP 다.** NAT Gateway 가 나중에 이 EIP 를 그대로
물기 때문에, 지금 등록하는 IP 와 나중에 실제로 나가는 IP 가 일치한다. 재등록할 일이 없다.

> S3 엔드포인트는 `route_table_ids` 를 직접 걸지 않고 연결을 별도 리소스로 뺐다.
> 직접 걸면 **생성되는 순간** private route table 에 prefix-list 라우트가 들어가고, 그
> 시점에 S3 로 가던 연결(앱 파일 업로드 · ECR 레이어 pull)이 끊긴다. "만들어만 두는"
> 단계가 무해하려면 연결이 별도 리소스여야 한다.

---

## 3-b. 외부 업체 허용목록 등록 — ⏳ 대기 중 (차단 조건)

**[`egress-ip-allowlist.md`](../handoff/egress-ip-allowlist.md) 의 등록 완료 회신이 3-d 의 착수 조건이다.**

등록 대상은 **우리가 나갈 때의 출발지 IP** 다. 상대 콜백/웹훅(인바운드)은 ALB 로 들어오므로
이번 변경과 무관하며, 질의서에도 그 구분을 명시해 두었다.

우리 인프라는 이 단계에서 아무것도 바꾸지 않는다. 기존 IP 로 계속 나가고 있으므로
**등록이 끝날 때까지 아무 영향이 없다.**

---

## 3-c. NAT Gateway 생성 — ⬜ 미착수

등록 완료 회신을 받은 뒤에 한다. **이 단계도 트래픽을 바꾸지 않는다.**

```hcl
# environments/shared/variables.tf
create_nat_gateway = true
```

```bash
terraform -chdir=environments/shared plan     # 1 to add 여야 한다
terraform -chdir=environments/shared apply
```

확인:

```bash
aws ec2 describe-nat-gateways --profile groble-terraform --region ap-northeast-2 \
  --filter "Name=vpc-id,Values=vpc-027616e8054f60abb" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State,Subnet:SubnetId,IP:NatGatewayAddresses[0].PublicIp}' --output table
```

- `State` 가 **available** 이 될 때까지 기다린다 (1~2분). pending 상태에서 3-d 로 넘어가지 말 것
- `Subnet` 이 **`subnet-089b27f99fdaee7eb`**(10.0.2.0/24, **2c**)인지
- `IP` 가 **`15.165.223.110`** 인지 — 등록한 IP 와 다르면 즉시 중단한다

---

## 3-d. 경로 전환 — ⬜ 미착수 (사용자 영향 있음)

> ✅ **선행 조건이던 [RDS MySQL 8.4 전환](./adhoc/rds-mysql-84-upgrade.md)은 2026-08-29 종결됐다.**
> 이 항목은 더 이상 3-d 를 막지 않는다. 남은 차단 조건은 **3-b(외부 업체 허용목록 등록)** 뿐이다.
>
> 판단 근거는 남겨 둔다 (2026-08-28 결정) — 두 작업의 blast radius 가 결제 경로에서 겹쳤다.
> 이쪽은 앱 → PG(페이플) **아웃바운드**를 갈아끼우고, RDS 전환은 결제 **쓰기**를 막는다.
> **같은 날 했다면 결제가 깨졌을 때 원인이 NAT 인지 DB 인지 가릴 수 없었다.**
> 앞으로도 결제 경로를 건드리는 작업끼리는 같은 창에 넣지 않는다.
>
> RDS 전환은 실제로 **쓰기 차단 35초 + 앱 재연결 문제로 7~8분 쓰기 실패**가 났다.
> 분리해 두길 잘한 사례로 기록해 둔다.

**스위치 두 개를 한꺼번에 켜지 않는다.** 하나씩 켜고 각각 검증한다. 같이 켜면 egress 가
깨졌을 때 NAT Gateway 탓인지 S3 엔드포인트 탓인지 갈리지 않는다.

### ① 기본 경로를 NAT Gateway 로

```hcl
use_nat_gateway = true
```

```bash
terraform -chdir=environments/shared plan
```

**plan 을 반드시 육안 확인한다:**

- `module.ecs_cluster.aws_route.private_nat_route` 가 **`~ update in-place`** 여야 한다
- **`-/+ replace`(destroy → create)로 나오면 중단한다.** 그 사이 기본 경로가 사라져
  egress 가 통째로 블랙홀이 된다. 그때는 아래 [CLI 원자 교체](#급할-때--cli-원자-교체)로 바꾸고
  `terraform apply -refresh-only` 로 state 를 맞춘다

검증이 끝나기 전에는 ②로 넘어가지 않는다.

### ② S3 트래픽을 엔드포인트로

```hcl
attach_s3_endpoint_to_private_rt = true
```

이 apply 로 private route table 에 S3 prefix-list 라우트가 들어간다. **진행 중이던 S3
연결이 다시 한 번 끊긴다** (①에서 이미 한 번 끊겼다).

---

## 검증

### 전환 직후 (①번 다음)

```bash
# 모니터링 노드 경유로 prod 노드에 들어가서 확인한다
ssh -i <key>.pem ubuntu@10.0.1.193
ssh 10.0.11.62
```

- [ ] **나가는 IP 가 바뀌었는가** — 가장 확실한 한 방이다
  ```bash
  curl -s https://checkip.amazonaws.com     # 15.165.223.110 이어야 한다
  ```
- [ ] 외부 도달 — `curl -I https://api.ecr.ap-northeast-2.amazonaws.com`
- [ ] 라우트 실제 반영
  ```bash
  aws ec2 describe-route-tables --profile groble-terraform --region ap-northeast-2 \
    --route-table-ids rtb-018b6acaf55855f9b \
    --query 'RouteTables[0].Routes[].{Dest:DestinationCidrBlock,PList:DestinationPrefixListId,ENI:NetworkInterfaceId,NATGW:NatGatewayId}' --output table
  ```
- [ ] NAT Gateway 지표에 트래픽이 잡히는가 — CloudWatch `BytesOutToDestination`
- [ ] **ECR pull 실검증** — **dev 환경으로** 테스트 배포 1회. prod 로 하지 않는다
- [ ] 결제 경로 이상 없음 — Grafana 결제 알림(R1~R9) 무발화, ALB 5xx 기준선 유지

### ②번 다음

- [ ] 라우트 테이블에 **prefix-list 라우트**(`pl-*` → `vpce-0db4b7f990ea3d315`)가 보이는가
- [ ] private 노드에서 S3 접근 — `aws s3 ls s3://<loki-bucket>/ --region ap-northeast-2`
- [ ] ECR pull 재검증 (레이어가 S3 에서 오므로 경로가 또 바뀌었다)

### 중단 기준

[이관 절차 목차의 Abort 기준](README.md)을 그대로 따른다.
추가로 **`checkip` 결과가 `15.165.223.110` 이 아니면** 무언가 잘못된 것이므로 롤백한다.

---

## 롤백

### 급할 때 — CLI 원자 교체

Terraform 을 거치지 않는 것이 가장 빠르다. `ReplaceRoute` 는 원자적이라 경로가 비는 순간이 없다.

```bash
aws ec2 replace-route --profile groble-terraform --region ap-northeast-2 \
  --route-table-id rtb-018b6acaf55855f9b \
  --destination-cidr-block 0.0.0.0/0 \
  --network-interface-id eni-0bbe59a160c2985ad
```

S3 엔드포인트까지 되돌리려면:

```bash
aws ec2 modify-vpc-endpoint --profile groble-terraform --region ap-northeast-2 \
  --vpc-endpoint-id vpce-0db4b7f990ea3d315 \
  --remove-route-table-ids rtb-018b6acaf55855f9b
```

**되돌린 뒤 반드시 코드도 맞춘다** — `use_nat_gateway = false`,
`attach_s3_endpoint_to_private_rt = false` 로 되돌리고 `terraform plan` 이 **No changes** 인지 확인한다.
안 맞춰 두면 다음 apply 가 다시 전환해 버린다.

### 여유가 있을 때 — 스위치 되돌리기

```hcl
use_nat_gateway                  = false
attach_s3_endpoint_to_private_rt = false
```

```bash
terraform -chdir=environments/shared apply
```

### ⚠️ 롤백도 공짜가 아니다

**되돌리는 순간 진행 중이던 연결이 또 한 번 전부 끊긴다.** "일단 해보고 이상하면 되돌린다"가
무료가 아니라는 뜻이다. 한 번에 성공시킬 준비를 하고 들어간다.

모니터링 노드의 `source_dest_check = false` 와 iptables MASQUERADE 를 **그대로 두었기 때문에**
되돌리면 즉시 복구된다. 이것들은 Phase 4(노드 재구축)까지 건드리지 않는다.

---

## 알아두어야 할 것

### 무엇이 끊기고 무엇이 안 끊기나

private route table 의 `0.0.0.0/0` 만 바뀌므로 **VPC 내부 통신은 전부 무관하다.**

| 끊기지 않음 | 끊김 |
|---|---|
| ALB → API 태스크 (사용자 요청 처리) | ECR pull |
| API → Redis / RDS | 외부 API·PG 아웃바운드 |
| API → OTLP (모니터링 노드 사설 IP) | SSM · 패키지 · S3 |
| Prometheus 스크레이프 | |

끊기는 이유는 두 겹이다. NAT 상태(conntrack)가 모니터링 노드 **안에** 있어 NAT Gateway 는 그
흐름을 모르고, SNAT 출발지 IP 도 바뀐다. 상대 서버는 낯선 IP 에서 시퀀스 중간부터 오는
패킷을 RST 로 끊거나 버린다.

### 커넥션 풀의 죽은 keep-alive

앱이 외부로 유지하던 idle 커넥션은 전환 후 **살아 있는 것처럼 보이지만 실제로는 끊긴 상태**가
된다. 그래서 영향이 "교체 순간 1초"로 끝나지 않고, 풀 안의 죽은 커넥션이 하나씩 뽑혀 나갈
때까지 **산발적인 첫-요청 실패**로 몇 분간 이어질 수 있다. 재시도가 있으면 흡수된다.

### cross-AZ 가 한시적으로 생긴다

private route table 이 **하나뿐**이라 2a(prod)·2c(dev)가 같은 경로를 쓴다. NAT Gateway 는
2c 에 있으므로 **prod 노드(2a)의 아웃바운드가 전환 후 cross-AZ 가 된다** (양방향 $0.01/GB).

의도한 것이다 — 계획서 §2.2 의 "전 구성요소 2c 정렬"을 미리 맞춘 것이고, **[Phase 9](./phase-09-prod-asg.md) 에서
prod 가 2c 로 넘어가면 해소된다.** 계획서가 "2c 정렬로 비용이 준다"고 말하는 것은 완료
상태 기준이며, Phase 3~8 사이 몇 주는 예외다.

### 모니터링 노드 알람은 아직 prod 채널이다

[`environments/shared/main.tf`](../../environments/shared/main.tf) 의 알람 채널 주석이
"Phase 3·6 이후 dev 로 내린다"고 적고 있으나, **Phase 3 만으로는 내리지 않는다.** NAT 겸직이
빠져도 관측·bastion·VPN 은 그대로라 여전히 prod-critical 이다. **Phase 4 이후에 조정한다.**

### 이번에 건드리지 않는 것

롤백 여지를 남기려고 그대로 둔다. 전부 Phase 4·10 의 몫이다.

- 모니터링 노드의 `source_dest_check = false`
- 노드 안의 iptables MASQUERADE
- 모니터링 SG 의 NAT 용 all TCP/UDP 허용 규칙
- 라우트 리소스가 `platform/ecs-cluster` 모듈에 있는 것 (원래 `infrastructure/vpc` 가 맞다).
  옮기면 destroy → create 가 되어 egress 가 비는 순간이 생기므로 **Phase 12 로 미룬다**

---

[← Phase 2 — 관측 선행 전환](./phase-02-observability.md) · [이관 절차 목차](README.md) · [다음: Phase 4 — 모니터링 노드 재구축 →](./phase-04-monitoring-node-rebuild.md)
