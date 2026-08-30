# 개발자 접근 경로 — WireGuard 없이 EC2·RDS 접속하기

> **참조 문서.** SSM Session Manager 로 로컬에서 바로 붙는 방법을 정리한다.
> 대상: 백엔드 개발자 · 인프라.
>
> 기존 경로(WireGuard VPN → 모니터링 노드 SSH → private 노드)를 대체한다.
> **VPN 도, SSH 키도, 22번 포트도 필요 없다.**

---

## 왜 바뀌었나

기존에는 private 서브넷의 노드에 닿으려면 WireGuard 로 VPN 을 붙고 bastion(모니터링 노드)을
거쳐야 했다. [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 에서 ECS 인스턴스 역할에
`AmazonSSMManagedInstanceCore` 를 붙이면서 **네 노드 모두 SSM 으로 직접 접속**할 수 있게 됐다.

| | 기존 | 지금 |
|---|---|---|
| 진입 | WireGuard VPN → bastion SSH → 대상 노드 | **로컬에서 바로** |
| 인증 | SSH 키 공유 | **AWS IAM** (개인별) |
| 인바운드 포트 | 22 · 51820 개방 필요 | **열지 않는다** — 노드가 SSM 으로 아웃바운드 연결을 맺는다 |
| 감사 | 없음 | **CloudTrail 에 누가·언제·어느 노드가 남는다** |

> WireGuard·bastion·22번 포트의 실제 폐기는 [Phase 9](./runbook/phase-09-access-path.md) 에서 한다.
> 그때까지는 두 경로가 병존한다.

---

## 준비 (한 번만)

### 1. Session Manager 플러그인

```bash
brew install session-manager-plugin
```

> ⚠️ `aws ssm start-session` 은 이 플러그인이 있어야 동작한다.
> 플러그인 없이도 `aws ssm send-command`(일회성 명령)는 쓸 수 있다.

### 2. AWS 프로필

AWS IAM Identity Center(SSO) 를 쓴다. 아래는 예시이며 **관리자에게 권한 세트를 받아야 한다**.

```bash
aws configure sso --profile groble
# SSO start URL / region: ap-northeast-2 / 계정: 538827147369
aws sso login --profile groble
```

이 문서의 명령은 전부 `--profile groble` 을 붙인 형태로 적었다. 프로필명은 각자 다를 수 있다.

### 3. 필요한 IAM 권한 — **관리자가 부여한다**

개발자 권한 세트에 아래를 넣으면 된다. 계정의 `Cluster=groble-cluster` 태그가 붙은
노드에만 접속할 수 있게 제한한 형태다.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FindInstances",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation"],
      "Resource": "*"
    },
    {
      "Sid": "StartSessionOnGrobleNodes",
      "Effect": "Allow",
      "Action": "ssm:StartSession",
      "Resource": "arn:aws:ec2:ap-northeast-2:538827147369:instance/*",
      "Condition": {
        "StringEquals": { "ssm:resourceTag/Cluster": "groble-cluster" }
      }
    },
    {
      "Sid": "AllowSessionDocuments",
      "Effect": "Allow",
      "Action": "ssm:StartSession",
      "Resource": [
        "arn:aws:ssm:ap-northeast-2::document/SSM-SessionManagerRunShell",
        "arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSession",
        "arn:aws:ssm:ap-northeast-2::document/AWS-StartPortForwardingSessionToRemoteHost"
      ]
    },
    {
      "Sid": "ManageOwnSession",
      "Effect": "Allow",
      "Action": ["ssm:TerminateSession", "ssm:ResumeSession"],
      "Resource": "arn:aws:ssm:*:*:session/${aws:userid}-*"
    }
  ]
}
```

> **prod 노드를 빼고 싶다면** `StartSessionOnGrobleNodes` 의 조건을
> `"ssm:resourceTag/Type": ["Development", "Monitoring"]` 로 바꾼다.

---

## 노드 목록

| 노드 | 인스턴스 ID | 위치 | 무엇이 도나 |
|---|---|---|---|
| `groble-develop-instance` | `i-0c8870fff57255a76` | private 2c | dev API · dev MySQL · dev Redis |
| `groble-prod-instance-1` | `i-08b4f8ffb95a89090` | private 2a | **prod API · prod Redis** |
| `groble-monitoring-v2-instance` | `i-0e8ca2a8866ca0384` | private 2c | Grafana · Prometheus · Loki · otelcol |
| `groble-nat-instance` | `i-08f515e6165426909` | public 2a | NAT · bastion · WireGuard (관측 스택은 빠졌다) |

ID 를 외울 필요는 없다. 이름으로 찾는 함수를 셸 설정에 넣어 두면 편하다.

```bash
# ~/.zshrc
gnode() {
  aws ec2 describe-instances --profile groble \
    --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}
gssh() { aws ssm start-session --profile groble --target "$(gnode "$1")"; }
```

```bash
gssh groble-develop-instance
```

---

## 1. EC2 접속

```bash
aws ssm start-session --profile groble --target i-0c8870fff57255a76
```

`ssm-user` 로 붙는다. 루트가 필요하면:

```bash
sudo su -
```

자주 쓰는 것들:

```bash
docker ps                      # 컨테이너 목록
docker logs -f <container>     # 컨테이너 로그
systemctl status ecs           # ECS 에이전트 상태
cat /etc/groble-node-info      # 이 노드가 뭔지 (신 모니터링 노드에만 있다)
```

> 💡 **로그를 보려는 것이라면 노드에 들어갈 필요가 없다.** Grafana 의 Loki 데이터소스에서
> `{app="groble", env="production"}` 으로 조회하는 편이 빠르다. → https://monitor.groble.im

---

## 2. RDS 접속 (포트 포워딩)

RDS 보안그룹은 **CIDR 인그레스가 하나도 없고** SG 참조만 허용한다.
따라서 **노드를 경유해야 한다.**

| 경유 노드 | RDS 3306 | 비고 |
|---|---|---|
| **모니터링 노드** | ✅ | **이걸 쓴다** — prod 를 건드리지 않는다 |
| prod 노드 | ✅ | 가능하지만 prod 다. 메모리 여유가 빠듯하니 피할 것 |
| **dev 노드** | ❌ | **안 된다.** RDS SG 에 dev SG 참조가 없다 (dev 는 컨테이너 MySQL 을 쓴다) |

```bash
aws ssm start-session --profile groble \
  --target i-0e8ca2a8866ca0384 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["groble-prod-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["13306"]}'
```

터미널을 열어 둔 채 다른 창에서:

```bash
mysql -h 127.0.0.1 -P 13306 -u groble_root -p
```

DBeaver·DataGrip 등 GUI 도 `127.0.0.1:13306` 으로 붙이면 된다.

> ⚠️ **MySQL 9.x 클라이언트로는 접속되지 않는다.** 계정 `groble_root` 가
> `mysql_native_password` 를 쓰는데 9.x 가 그 플러그인을 제거했다.
> **8.x 클라이언트**나 `pymysql` 을 쓸 것.
>
> ```bash
> brew install mysql-client@8.4
> ```

---

## 3. Grafana · Prometheus · Loki 를 로컬 브라우저로

Grafana 는 ALB 로 열려 있다 → https://monitor.groble.im

**Prometheus(9090)·Loki(3100) 는 ALB 에 노출되어 있지 않다.** 포트 포워딩이 유일한 경로다.

```bash
aws ssm start-session --profile groble \
  --target i-0e8ca2a8866ca0384 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9090"],"localPortNumber":["9090"]}'
```

→ http://localhost:9090 (Prometheus). `3100`(Loki) 도 같은 방식이다.

---

## 4. 명령 한 줄만 실행 (플러그인 없이)

```bash
CMD=$(aws ssm send-command --profile groble \
  --instance-ids i-0c8870fff57255a76 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["docker ps --format \"{{.Names}}\""]' \
  --query 'Command.CommandId' --output text)

aws ssm get-command-invocation --profile groble \
  --command-id "$CMD" --instance-id i-0c8870fff57255a76 \
  --query StandardOutputContent --output text
```

CI 나 스크립트에서 쓰기 좋다.

---

## 주의사항

- **prod 노드는 조심해서.** 메모리 여유가 빠듯하다. 무거운 명령(대용량 `grep`, `docker build` 등)은
  피하고, 조회는 가능하면 Grafana·Loki 로 갈음할 것
- **세션은 CloudTrail 에 남는다.** 누가 언제 어느 노드에 붙었는지 추적된다
- **컨테이너 안으로 직접 들어가는 것(ECS Exec)은 아직 안 된다.** 서비스의
  `enableExecuteCommand` 가 꺼져 있고 Task Role 에 SSM 채널 권한이 없다.
  필요하면 인프라에 요청할 것 — 노드에서 `docker exec` 로 우회할 수는 있다
- **아직 WireGuard 가 필요한 경우는 없다.** EC2 셸·RDS·모니터링 UI 세 가지가 모두 SSM 으로 덮인다.
  그래도 [Phase 9](./runbook/phase-09-access-path.md) 까지는 기존 경로를 남겨 둔다

## 안 될 때

| 증상 | 원인 |
|---|---|
| `SessionManagerPlugin is not found` | 플러그인 미설치 → `brew install session-manager-plugin` |
| `is not authorized to perform: ssm:StartSession` | IAM 권한 → 관리자에게 위 정책 요청 |
| `TargetNotConnected` | 노드의 SSM 에이전트가 죽었거나 아웃바운드가 막혔다. 인프라에 문의 |
| 포트 포워딩은 붙는데 MySQL 이 인증 실패 | MySQL 9.x 클라이언트 문제 (위 참조) |
| `Error loading SSO Token` | `aws sso login --profile groble` 다시 실행 |
