# [요청] Dev DB 를 컨테이너 MySQL → RDS 로 전환해 주세요

| | |
|---|---|
| **요청 대상** | groble-backend |
| **요청자** | 인프라 (groble-infra) |
| **작성일** | 2026-08-31 |
| **상태** | ⏳ **회신 대기** — RDS 는 만들어 두었습니다. **전환 작업과 완료 연락**을 부탁드립니다 |
| **관련** | [Phase 8-a 런북](../runbook/phase-08a-dev-rds.md) · [SSM 접속 가이드](../developer-access.md) |

---

## 1. 한 줄 요약

**Dev DB 용 RDS 를 만들어 두었습니다.** 데이터 이관과 `DB_HOST` 전환을 부탁드립니다.
**바꾸실 값은 `DB_HOST` 하나뿐이고**, 나머지 접속 정보는 지금 쓰시는 것과 전부 같습니다.

전환이 끝나면 알려주세요 — **구 MySQL 컨테이너는 저희가 정리합니다.** 그 전까지는 살려 둡니다(롤백용).

**Prod 는 이 작업과 무관합니다.** Dev 만 바뀝니다.

---

## 2. 왜 바꾸나

지금 Dev MySQL 은 **개발 노드의 로컬 디스크에 붙은 컨테이너**입니다. 세 가지 문제가 있습니다.

1. **백업이 없습니다.** 노드가 죽으면 데이터가 사라집니다
2. **메모리 한도(256 MiB)에 붙어 있습니다** — 실사용 253.3 MiB(**98.9%**). 지난 14일에 **5번 재시작**했고,
   종료된 컨테이너들이 전부 한도에 붙은 채였습니다. 여러분이 겪으셨을 수 있는 dev DB 순단의 원인입니다
3. **엔진이 prod 와 다릅니다** — dev 는 **8.0.46**, prod 는 **8.4.11**.
   "dev 에서 통과했으니 prod 로 올린다"는 검증이 DB 계층에서는 성립하지 않습니다

전환 후에는 자동 백업(7일)이 붙고, 버퍼풀이 128 → **256 MiB** 로 늘고, **엔진이 prod 와 같아집니다.**

> **8.4 호환성은 이미 확인된 사항입니다.** 2026-08-29 prod 를 8.0 → 8.4 로 올릴 때
> 검토해 주셨던 그 건입니다 ([당시 요청서](./closed/rds-mysql-84-compatibility.md)).
> Dev 도 같은 8.4.11 을 씁니다.

---

## 3. 접속 정보

| 항목 | 값 |
|---|---|
| **호스트** | `groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com` |
| 포트 | `3306` |
| 데이터베이스 | `groble_develop_database` |
| 사용자 | `groble_root` |
| **비밀번호** | **지금 쓰시는 값 그대로입니다** (아래 참조) |
| 엔진 | MySQL **8.4.11** |
| 위치 | private subnet `ap-northeast-2c` — 개발 노드와 같은 AZ. 인터넷에서 직접 닿지 않습니다 |

### 🟢 바꾸실 값은 `DB_HOST` 하나입니다

RDS 마스터 계정을 **앱이 지금 쓰는 것과 같은 자격증명으로** 만들었습니다.
현재 태스크 정의(`groble-dev-task:1188`)의 값과 대조해 확인했습니다.

| 환경변수 | 지금 | 바꾸나 |
|---|---|---|
| `DB_HOST` | `10.0.12.215` | **✅ 위 호스트로** |
| `DB_PORT` | `3306` | ❌ 그대로 |
| `DB_NAME` | `groble_develop_database` | ❌ 그대로 |
| `DB_USERNAME` | `groble_root` | ❌ 그대로 |
| `DB_PASSWORD` | — | ❌ **그대로** (같은 값입니다) |

### 접속 확인하는 법

**개발 노드에서** (SSM, VPN 불필요 — [접속 가이드](../developer-access.md)):

```bash
aws ssm start-session --profile groble --target i-0c8870fff57255a76
```

노드에 mysql 클라이언트를 설치하실 필요 없습니다. **MySQL 컨테이너 안의 것을 쓰시면 됩니다**
(host 네트워크 모드라 RDS 에 그대로 닿습니다):

```bash
C=$(docker ps -q --filter name=groble-dev-mysql)
RDS=groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com

docker exec -it "$C" sh -c "mysql -h $RDS -u groble_root -p\"\$MYSQL_ROOT_PASSWORD\" groble_develop_database"
```

**로컬 PC 에서** 붙고 싶으시면 모니터링 노드를 경유한 포트 포워딩을 쓰세요:

```bash
aws ssm start-session --profile groble --target i-0e8ca2a8866ca0384 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["13306"]}'
```

그 뒤 `127.0.0.1:13306` 으로 접속하시면 됩니다.

> ⚠️ **MySQL 9.x 클라이언트는 피하세요.** prod 접속 시 알려진 문제인데, dev RDS 는 8.4 라
> 9.x 로도 붙긴 합니다. 다만 도구를 통일하시는 편이 헷갈리지 않습니다. 8.x 클라이언트나 `pymysql` 을 권합니다.

---

## 4. 전환 절차

**저희가 리허설로 한 번 돌려 검증한 절차입니다.** 아래 소요 시간은 실측값입니다.

### 준비 — 현재 RDS 상태

리허설 데이터는 지웠고 **빈 `groble_develop_database`** 만 있습니다
(문자셋 `utf8mb4` / `utf8mb4_0900_ai_ci` — 지금 컨테이너와 같습니다).

### 0) 시점 선택

**쓰기가 막히는 구간은 1분 미만**입니다(덤프 1초 + 복원 15초 + 대조). 그 뒤 앱 재배포 시간이 더 걸립니다.
개발 작업이 없는 시간대를 잡아 주시고, 팀에 공지해 주세요.

### 1) 쓰기 동결 🔴 이 단계를 건너뛰면 데이터가 유실됩니다

```bash
C=$(docker ps -q --filter name=groble-dev-mysql)
docker exec "$C" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL read_only = ON;"'
```

> **왜 필요한가**: 덤프를 뜬 뒤 배포가 끝날 때까지 앱은 **여전히 컨테이너에 쓰고 있습니다.**
> 게다가 Blue/Green 배포라 전환 순간 **구 버전(컨테이너)과 신 버전(RDS)이 서로 다른 DB 를 보며
> 동시에 살아 있습니다.** 그 사이의 쓰기는 어느 쪽이 살아남을지 보장되지 않습니다.
>
> `groble_root` 에는 SUPER 권한이 없어 이 설정으로 **앱의 쓰기가 실제로 막힙니다.** 읽기는 계속됩니다.
> 되돌리기는 `SET GLOBAL read_only = OFF;` 한 줄입니다.
>
> ⚠️ **컨테이너가 재시작하면 `OFF` 로 돌아갑니다.** 작업 중에 `docker ps` 로 한 번씩 확인해 주세요
> (이 컨테이너는 14일에 5번 재시작한 이력이 있습니다).

### 2) 덤프 → 복원 (실측 16초)

```bash
C=$(docker ps -q --filter name=groble-dev-mysql)
RDS=groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com
DB=groble_develop_database

# 대상 비우기 (혹시 남은 것이 있으면)
docker exec "$C" sh -c "mysql -h $RDS -u groble_root -p\"\$MYSQL_ROOT_PASSWORD\" \
  -e 'DROP DATABASE IF EXISTS \`$DB\`; CREATE DATABASE \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;'"

# 덤프
docker exec "$C" sh -c "mysqldump -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \
  --single-transaction --no-tablespaces --routines --triggers --events \
  --hex-blob --default-character-set=utf8mb4 $DB" 2>/dev/null > /tmp/dev-final.sql

# 복원
docker exec -i "$C" sh -c "mysql -h $RDS -u groble_root -p\"\$MYSQL_ROOT_PASSWORD\" $DB" < /tmp/dev-final.sql
```

> **`mysql` 스키마는 절대 덤프하지 마세요.** RDS 마스터 계정을 덮어써 접속이 끊깁니다.
> 위 명령은 `groble_develop_database` 하나만 뜹니다.

### 3) 대조 — 🔴 어긋나면 진행하지 마세요

`information_schema.table_rows` 는 추정치라 쓸 수 없습니다. 실제 `COUNT(*)` 를 돌립니다.

```bash
docker exec "$C" sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
  -e \"SELECT table_name FROM information_schema.tables \
       WHERE table_schema='$DB' AND table_type='BASE TABLE' ORDER BY table_name\"" \
  2>/dev/null > /tmp/tables.txt

while read -r t; do
  b=$(docker exec "$C" sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
        -e 'SELECT COUNT(*) FROM \`$DB\`.\`$t\`'" 2>/dev/null)
  a=$(docker exec "$C" sh -c "mysql -h $RDS -u groble_root -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
        -e 'SELECT COUNT(*) FROM \`$DB\`.\`$t\`'" 2>/dev/null)
  [ "$b" = "$a" ] && echo "ok   $t $b" || echo "MISMATCH $t: 컨테이너=$b RDS=$a"
done < /tmp/tables.txt | tee /tmp/rowdiff.txt

grep -c '^ok' /tmp/rowdiff.txt    # 테이블 수와 같아야 합니다
grep MISMATCH /tmp/rowdiff.txt    # 아무것도 안 나와야 합니다
```

**리허설 때의 기준값** (2026-08-31): 테이블 **110**, 총 행 수 **51,492**, 인덱스 **567**.
지금은 늘어 있을 테니 자릿수 감각으로만 보세요. 중요한 것은 **양쪽이 같은가**입니다.

### 4) `DB_HOST` 전환 후 배포

**평소 하시는 대로 배포하시면 됩니다.** `DB_HOST` 만 위 RDS 호스트로 바꿔 주세요.

> **저희 쪽에서 배포해 드릴 수 없는 이유**를 적어 둡니다.
> 실행 중인 태스크 정의를 등록하는 것은 **GitHub Actions(`groble-github-actions`)** 입니다.
> ```
> groble-dev-task:1181  ← Terraform 이 만든 것. 아무도 실행하지 않습니다
> groble-dev-task:1188  ← 실제로 서비스가 돌리는 것
> ```
> ECS 서비스에 `ignore_changes = [task_definition]` 가 걸려 있어 **Terraform 이 만든 리비전은
> 배포되지 않습니다.** 즉 `DB_HOST` 의 실효값은 파이프라인이 정합니다. 값이 어디에 있는지
> (task-definition 템플릿인지 Actions variable 인지)는 앱 리포지토리를 보셔야 합니다.

### 5) 확인

- [ ] 새 태스크가 healthy
- [ ] **RDS 쪽에 앱 커넥션이 보이는지** — `SHOW PROCESSLIST` 에 dev 태스크 IP
- [ ] **컨테이너 쪽에 앱 커넥션이 남아 있지 않은지**
- [ ] 기능 스모크 테스트 (특히 쓰기 경로)

### 6) 마무리

컨테이너의 `read_only` 는 **켜 둔 채로 두세요.** 앱은 이미 RDS 를 보므로 영향이 없고,
롤백용 데이터가 더 갈라지지 않습니다.

---

## 5. 되돌리기

**컨테이너 MySQL 은 그대로 살아 있습니다.** 저희가 지우기 전까지는 언제든 되돌릴 수 있습니다.

1. `SET GLOBAL read_only = OFF;`
2. `DB_HOST` 를 `10.0.12.215` 로 되돌려 배포

> 되돌리면 **전환 후 RDS 에 쓰인 데이터는 잃습니다.** Dev 이므로 감수 가능한 범위라고 봅니다.

---

## 6. 알아두시면 좋은 것

**① 연결이 TLS 로 암호화됩니다.** 컨테이너 구간은 평문이었는데, RDS 는 인증서를 제시하고
MySQL 8 클라이언트 기본값이 `--ssl-mode=PREFERRED` 라 자동으로 협상됩니다.
저희 CLI 테스트에서는 `TLS_AES_256_GCM_SHA384` 로 붙었습니다.
**Connector/J 도 기본값이 `sslMode=PREFERRED` 라 같을 것으로 보이나, 확인은 5번 단계에서 부탁드립니다.**

**② `caching_sha2_password` 는 문제가 되지 않습니다.** RDS 8.4 의 마스터 계정이 이 플러그인을 쓰는데,
**지금 컨테이너의 `groble_root` 도 이미 같은 플러그인**입니다(공식 `mysql:8.0` 이미지 기본값).
평문 연결에서도 붙고 있으니 앱 설정은 이미 통과하는 경로입니다.

**③ DEFINER 문제가 없습니다.** dev DB 에 view · trigger · stored procedure · event 가 **0건**이라
복원 시 권한 문제가 발생하지 않습니다.

**④ 콜레이션이 두 가지로 갈려 있습니다** — `utf8mb4_0900_ai_ci` 52개 / `utf8mb4_unicode_ci` 58개.
**이관이 이것을 바꾸지도 고치지도 않습니다**(덤프가 테이블별 콜레이션을 그대로 들고 갑니다).
다만 서로 다른 콜레이션 컬럼을 조인하면 인덱스를 못 쓰므로, 언젠가 정리하실 만합니다
([향후 개선 Low-6](../infra-future-improvements.md#low-6)). **이번 작업과는 무관합니다.**

**⑤ 백업·점검 시간** — 자동 백업 KST **02:00~03:00**, 점검창 **월요일 03:00~04:00**. 보존 7일.

---

## 7. 끝나면 알려주세요

**"Dev DB 이관 완료"** 한 줄이면 충분합니다. 그러면 저희가:

1. 구 MySQL 컨테이너 서비스를 제거하고
2. `컨테이너 메모리 하드리밋 근접` 알람이 멎는지 확인하고
3. 노드의 데이터 디렉터리를 정리합니다

**2~3일 정도 쓰시면서 이상이 없는 것을 보신 뒤에 알려주셔도 됩니다.** 급하지 않습니다 —
그때까지 컨테이너를 살려 두는 것이 곧 롤백 수단입니다.

## 8. 막히시면

이 문서로 해결되지 않는 것이 있으면 인프라 쪽에 알려주세요. 특히:

- RDS 에 접속이 안 되는 경우 (보안그룹 문제일 수 있습니다)
- 복원 중 오류가 나는 경우 (덤프 옵션 조정이 필요할 수 있습니다)
- 행 수 대조가 어긋나는 경우 — **이때는 진행하지 마시고 먼저 알려주세요**
