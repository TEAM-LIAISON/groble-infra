# RDS MySQL 8.0 → 8.4 업그레이드 (확장 지원 과금 중단)

> [이관 절차 목차](../infra-ha-migration-runbook.md) · Phase 와 독립적인 단발 작업이다. Phase 6(ElastiCache)·Phase 7(prod ASG)과 자원이 겹치지 않는다.

| | |
|---|---|
| **상태** | Terraform 사전 변경분 작성 완료(`feat/rds-mysql-84-upgrade`, apply 대기) · **DB 사전 확인 2건 통과.** 남은 것은 백엔드 회신 2건 — 아래 [사전 확인](#사전-확인) |
| **목적** | 2026-08-01 부터 자동 부과되기 시작한 **RDS Extended Support 과금(월 $178.56)을 멈춘다** |
| **사용자 영향** | Blue/Green 전환 시 **쓰기 차단 약 1분**. 그 외 무중단 |
| **되돌리기** | 전환 후 구 인스턴스(`-old1`)가 남으므로 **엔드포인트 되돌리기 가능**. 단 전환 후 쓰기분은 유실 |
| **일정** | **이번 주 내 (날짜는 담당자가 지정한다).** 시각만 실측 근거가 있다 — [아래](#d-day--스위치오버) |

---

## 1. 왜 하는가 — 검증된 비용 근거

Cost Explorer 실측이다. 계정에 크레딧이 걸려 있어 순청구액은 전 서비스 `$0` 으로 찍히므로,
**`RECORD_TYPE=Usage`(크레딧 상계 전 총사용액)** 로 조회해야 보인다.

동일한 1일~25일 구간 비교:

| RDS 사용유형 | 7/1~7/25 | 8/1~8/25 |
|---|---:|---:|
| `APN2-ExtendedSupport:Yr1-Yr2:MySQL8.0` | — | **$143.28** |
| `APN2-InstanceUsage:db.t3.micro` | $15.60 | $15.52 |
| `APN2-RDS:GP2-Storage` | $2.11 | $2.11 |
| **합계** | **$17.71** | **$160.91** |

**9.1배 증가, 증가분 $143.20 이 전액 확장 지원 단일 항목이다.** 인스턴스·스토리지 사용량은
소수점까지 동일하다 — 트래픽이나 구성 변경 때문이 아니다.

일별로 보면 경계가 칼같다. `2026-07-31 $0.00` → `2026-08-01 $5.76`, 이후 매일 정확히
48 vCPU-hour($5.76). db.t3.micro 는 2 vCPU 이므로 `2 vCPU × 24h × $0.12`.

> **⚠️ 마이너 업그레이드로는 해결되지 않는다.** 과금 항목명이 `...:MySQL8.0` 이다.
> 8.0.45 라는 마이너 버전이 아니라 **8.0 메이저 계열 자체**가 표준 지원 종료 대상이다.
> `8.0.46` 으로 올려도 과금은 그대로 유지된다. **8.4 로 메이저 업그레이드해야만 멈춘다.**
> 방치하면 Yr3 요율(통상 2배)로 한 번 더 오른다.

**지금 당장 현금이 나가지는 않는다** — 크레딧이 전액 상계 중이다. 실질 효과는 크레딧 소진
속도를 늦추는 것이고, 크레딧이 끝나는 순간부터 그대로 청구로 전환된다. 계정 전체 8월
사용액 $311.77 중 **RDS 하나가 52%** 다 (6·7월엔 10% 수준이었다).

### 이미 발생한 비용은 취소되지 않는다

이미 발생한 $143 은 소급 취소되지 않는다. 확장 지원은 구독료가 아니라 **인스턴스 시간처럼
시간 단위로 계량되는 사용량 과금**이라, 업그레이드는 **소급 환불이 아니라 계량기 정지**다.

| 8.4 전환 완료 시점 | 8월 확장 지원 합계 | 절감 |
|---|---:|---:|
| 8/26 | 약 $150 | 약 $29 |
| 8/31 | 약 $173 | 약 $6 |
| 미실시 | $178.56 | — |

**하루 미루는 비용은 $5.76 다.** 8월 안에 서두를 실익은 크지 않고, 의미 있는 효과는
전환 다음 달부터(월 $178.56 → $0) 나온다. **즉 일정은 비용이 아니라 아래 사전 확인이 결정한다.**

---

## 2. 현재 상태 (2026-08-26 실측)

| 항목 | 값 | 업그레이드 관점 |
|---|---|---|
| 엔진 | mysql **8.0.45** (`Deprecated: true`) | 대상 |
| 클래스 | db.t3.micro (2 vCPU / 1 GiB) | vCPU 2개라 확장 지원 요율이 인스턴스비의 9배 |
| AZ / Multi-AZ | ap-northeast-2**c** / **false** | 단일 AZ — in-place 시 완전 정지 |
| 스토리지 | gp2 20GB (→100GB 오토스케일), 암호화 | 그대로 승계 |
| 백업 | 7일, 03:00–04:00 **UTC** | B/G 전제조건 충족 |
| 점검창 | sun:04:00–05:00 **UTC** | |
| 파라미터그룹 | `groble-prod-mysql-params` (family `mysql8.0`) | **family 는 변경 불가 → 신규 생성 필요** |
| 사용자 지정 파라미터 | `max_connections=200` **단 1건** | 8.4 에도 존재·수정가능 ✅ |
| `binlog_format` | **MIXED** (system 기본값) | **B/G 는 ROW 필요 → 변경해야 함** |
| 읽기 복제본 | 없음 | 복잡도 없음 |
| 삭제 방지 | **true** | 구 인스턴스 정리 시 해제 필요 |
| 엔드포인트 | `groble-prod-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com` | **B/G 전환 후에도 동일** |

`innodb_buffer_pool_size` 는 커스텀 선언돼 있지만 값이 엔진 기본 수식과 같아 RDS 가
user-set 으로 잡지 않는다(`--source user` 조회 시 안 나옴). 실질 커스텀은 `max_connections` 하나뿐이라
**파라미터 이관 리스크가 거의 없다.**

### 앱 쪽 (groble-backend)

| 항목 | 값 | 8.4 호환 |
|---|---|---|
| Spring Boot | 3.5.16 | — |
| MySQL Connector/J | **미확정** (캐시에 `8.3.0`·`9.5.0` 공존) | ⏳ [③(b)](#-백엔드-회신---대기-중-2건) 확인 필요 |
| Flyway | **11.7.2** (`flyway-mysql`) | ✅ 8.4 지원 |
| DB 접속 정보 | `DB_HOST` 환경변수 = RDS 엔드포인트 | ✅ B/G 전환 시 **재배포 불필요** |

마이그레이션 스크립트는 219건이지만 **이미 적용 완료분이라 재실행되지 않는다.**
다만 dev 컨테이너(MySQL 8.0)와 Testcontainers 는 여전히 8.0 이라, **8.4 비호환 구문이 있어도
CI 가 잡아주지 못한다** — 아래 [부수 항목](#6-부수-항목-이번-범위-밖) 참조.

---

## 3. 방식 선택 — Blue/Green 을 쓴다

| | **A. In-place 업그레이드** | **B. RDS Blue/Green (권장)** |
|---|---|---|
| 다운타임 | **약 15~40분 완전 정지** | **쓰기 차단 약 1분** |
| 방법 | `modify-db-instance --allow-major-version-upgrade` | 8.4 그린 복제본 생성 후 스위치오버 |
| 사전 검증 | 불가 — 운영 DB에서 바로 실행 | **그린에서 실제 8.4 동작을 미리 확인 가능** |
| 롤백 | 스냅샷 복원만 가능 (30~60분, 엔드포인트 변경) | 구 인스턴스가 `-old1` 로 살아있음 |
| 추가 비용 | 없음 | 그린 인스턴스 병행 가동분 (db.t3.micro, 수 달러) |
| 전제조건 | 없음 | `binlog_format=ROW`, 자동백업 활성(✅), 커스텀 PG(✅) |

**단일 AZ + 결제 트랜잭션 경로**라는 조건에서 A의 15~40분 정지는 받아들이기 어렵다.
Redis 가 `checkout:idempotency:*` / `stock:reserved:*` 의 **유일한 권위 소스**라,
DB만 장시간 끊기면 "Redis 에는 예약이 잡혔는데 DB 기록은 실패한" 상태가 대량 발생한다.

> 이전 대화에서 in-place 다운타임을 "수 분"으로 말했는데, 메이저 버전 업그레이드는
> 사전 스냅샷 + 업그레이드 + 재부팅이 직렬로 일어나 **15~40분** 이 현실적이다. 계획 판단이 달라지는
> 차이라 바로잡는다.

---

## 4. ⚠️ 반드시 짚어야 할 위험 — ALB 헬스체크가 태스크를 죽인다

전환 자체보다 **이쪽이 더 위험하다.**

- `/actuator/health` 는 Spring Boot 기본 집계라 **DataSource 상태가 포함**된다.
  백엔드에 `health.group`(liveness/readiness) 이나 `db` 인디케이터 제외 설정이 **없다.**
  → DB 가 끊기면 `/actuator/health` 가 **503** 을 낸다.
- `groble-prod-blue-tg-v2` 의 `unhealthy_threshold = 2`, `interval = 30s`
  → **연속 실패 60초면 타깃 비정상 판정 → 등록 해제 → ECS 가 태스크 재시작.**
- prod 는 `desired_count = 1` 이다. **태스크 재시작 = 전면 중단**이고,
  Spring Boot 기동에 60~90초가 더 걸린다.

즉 **1분짜리 스위치오버가 3분짜리 전면 장애로 번질 수 있다.** 참고로 dev 타깃그룹은
`unhealthy_threshold = 5`(150초)로 여유가 있는데, prod 만 2로 빡빡하다.

**대응 — 전환 직전에 prod 타깃그룹 임계를 일시 완화하고, 끝나면 되돌린다.**

```bash
# 전환 직전 (blue/green 양쪽 모두)
for TG in groble-prod-blue-tg-v2 groble-prod-green-tg-v2; do
  ARN=$(aws elbv2 describe-target-groups --profile groble-terraform --region ap-northeast-2 \
        --names $TG --query 'TargetGroups[0].TargetGroupArn' --output text)
  aws elbv2 modify-target-group --profile groble-terraform --region ap-northeast-2 \
    --target-group-arn $ARN --unhealthy-threshold-count 5
done
```

전환 완료 검증 후 `--unhealthy-threshold-count 2` 로 되돌린다.
**되돌리지 않으면 Terraform 이 다음 apply 에서 되돌리며 drift 를 보고한다.**

---

## 5. 절차

### 사전 확인

**모두 끝나기 전에는 D-Day 를 잡지 않는다.**

| # | 항목 | 상태 |
|---|---|---|
| ① | 인증 플러그인 | ✅ 통과 — RDS 8.4 가 native password 를 켠 채 고정한다 |
| ② | 스키마 (MyISAM · utf8mb3) | ✅ 통과 — 106테이블 전부 InnoDB, utf8mb3 없음 |
| ③ | 백엔드 회신 (예약어 · Connector/J 버전) | ⏳ **대기** |
| ④⑤ | Terraform 사전 변경분 | ✅ 작성 완료, apply 대기 |

#### ① 인증 플러그인 — ✅ 확인 완료 (2026-08-26). **차단 요인 아니다**

운영 DB 실측 결과다.

| user | host | plugin |
|---|---|---|
| `groble_root` | `%` | **`mysql_native_password`** |
| `rds_superuser_role` | `%` | `mysql_native_password` (RDS 관리 롤, 로그인 계정 아님) |
| `rdsadmin` | `localhost` | `auth_socket` (RDS 내부 관리자, AWS가 관리) |
| `mysql.infoschema` / `mysql.session` / `mysql.sys` | `localhost` | `caching_sha2_password` |

**앱 계정 `groble_root` 가 `mysql_native_password` 를 쓰고 있다.** 업스트림 MySQL 8.4 는 이
플러그인을 기본 비활성화하므로 원래대로면 업그레이드 후 접속 전멸이다.

**그런데 RDS 는 다르다.** `mysql8.4` 파라미터그룹 기본값을 조회하면:

```
mysql_native_password   ParameterValue: ON   ApplyType: static   IsModifiable: false
authentication_policy   ParameterValue: *:caching_sha2_password  IsModifiable: true
```

**AWS 가 `ON` 으로 고정해 두었고 끌 수조차 없다**(`IsModifiable: false`). 즉 RDS MySQL 8.4 에서는
기존 native password 계정이 그대로 인증된다. `authentication_policy` 는 **신규 생성 계정의
기본 플러그인**만 정하므로 기존 계정에 영향이 없다.

> 앞서 이 항목을 "가장 큰 미확인 변수"로 분류했는데, RDS 가 업스트림과 다르게 동작한다.
> **인증 플러그인 때문에 업그레이드가 막히지는 않는다.**

**다만 부채로 남는다.** AWS 파라미터 설명 자체가 *"deprecated 이며 다음 메이저 릴리스에서
제거된다"* 고 못박고 있다. 9.x 이전에 반드시 옮겨야 하며, **이번 업그레이드와 분리해서**
진행하는 편이 낫다 (동시에 바꾸면 장애 원인 분리가 안 된다).

```sql
-- 8.0 상태에서 먼저, 별도 작업으로. 8.4 전환과 같은 날 하지 말 것
ALTER USER 'groble_root'@'%' IDENTIFIED WITH caching_sha2_password BY '<현재 비밀번호>';
```

> 전환 시 Connector/J 는 `caching_sha2_password` 협상에 서버 공개키가 필요하다.
> TLS 미사용이면 JDBC URL 에 `allowPublicKeyRetrieval=true` 가 필요할 수 있다.

**운영 메모:** 로컬 MySQL **9.x 클라이언트는 native password 계정에 접속하지 못한다**
(`mysql_native_password.so` 가 클라이언트에서 제거됐다). 점검 시 8.x 클라이언트나
`pymysql` 같은 대체 클라이언트가 필요하다.

#### ② 스키마 호환성 — ✅ 확인 완료 (2026-08-26). **문제 없음**

| 점검 | 결과 |
|---|---|
| 스토리지 엔진 | **106개 테이블 전부 InnoDB.** MyISAM 없음 |
| utf8mb3 (테이블 레벨) | **해당 없음** |
| utf8mb3 (컬럼 레벨) | **해당 없음** |

컬럼 레벨은 테이블 기본 콜레이션과 다를 수 있어 따로 확인했고, 역시 없다.

#### ③ 백엔드 회신 — ⏳ 대기 중 (2건)

**(a) 8.4 신규 예약어 충돌.** 219건의 Flyway 스크립트와 네이티브 쿼리에 8.4 예약어가
식별자로 쓰였는지 확인 요청. 이미 적용된 마이그레이션은 재실행되지 않으므로
**런타임 네이티브 쿼리가 실제 위험 지점이다.**

**(b) MySQL Connector/J 해석 버전 확정.** gradle 캐시에 `8.3.0` 과 `9.5.0` 이 함께 있어
현재 빌드가 어느 쪽을 쓰는지 오프라인으로 확정하지 못했다. **`./gradlew dependencies` 로 확인 필요.**

- `9.x` 면 문제 없다
- **`8.3.0` 이면 확인이 필요하다** — 8.3.0 은 MySQL 8.4 GA 이전 릴리스라 8.4 서버 조합이
  공식 검증 범위 밖이다. Connector/J `8.4+` 로 올리는 편이 안전하다

#### ④⑤ Terraform 사전 변경분 — ✅ 작성 완료, apply 대기

브랜치 **`feat/rds-mysql-84-upgrade`** 에 있다. 두 가지가 들어 있다.

| 변경 | 파일 | 이유 |
|---|---|---|
| 기존 8.0 그룹에 `binlog_format = ROW` | `modules/infrastructure/rds-mysql/main.tf` | B/G 전제조건. 동적 파라미터라 **재부팅 불필요** |
| `aws_db_parameter_group.mysql_params_84` 신설 (family `mysql8.4`) | 〃 | family 는 변경 불가 속성이라 기존 그룹을 고칠 수 없다. 같은 이름으로 replace 하면 destroy/create 가 이름 충돌로 맞물린다 |
| 출력 `mysql_84_parameter_group_name` | `modules/infrastructure/rds-mysql/outputs.tf`, `environments/prod/main.tf` | 아래 B/G 명령에 그대로 넘기기 위해 |

`innodb_buffer_pool_size` 는 8.4 그룹으로 옮기지 않았다. 8.0 에서도 값이 엔진 기본 수식과
같아 RDS 가 user-set 으로 잡지 않았고(`--source user` 조회 시 미출력), 옮기면 perpetual diff 만 생긴다.

**`terraform plan` 확인 결과 (2026-08-26):**

```
Plan: 1 to add, 1 to change, 0 to destroy.

  ~ aws_db_parameter_group.mysql_params        # + binlog_format = ROW
  + aws_db_parameter_group.mysql_params_84     # family = mysql8.4
  + output mysql_84_parameter_group_name = "groble-prod-mysql-84-params"
```

**RDS 인스턴스 자체에는 변경이 없고 destroy 도 없다.** 그린 생성 전 아무 때나 적용 가능하다.

```bash
cd environments/prod && terraform plan   # 위와 동일한지 확인 후
terraform apply
```

> ⚠️ **이 브랜치에는 스위치오버 이후 반영할 변경(`engine_version = "8.4"` 등)은 들어 있지 않다.**
> 미리 넣으면 apply 시 Terraform 이 **in-place 메이저 업그레이드를 시도**하기 때문이다.
> 해당 변경은 아래 [Terraform 정합화](#terraform-정합화--빠뜨리면-사고가-난다) 에 명세만 해 뒀고,
> **스위치오버가 끝난 뒤에 별도 커밋으로 만든다.**

---

### D-Day — 스위치오버

> **날짜는 담당자가 지정한다.** 아래 D-n 은 D-Day 기준 상대 일자일 뿐이다.

**시각만 근거가 있다 — KST 04:00~06:00 을 권한다.** 최근 14일 ALB RequestCount 실측상
이 구간이 최저다: 04시 1,666 req/h 로 피크(16시) 5,036 req/h 의 **1/3 수준**이다.
가장 나쁜 선택은 16시대다.

**최소 선행 시간은 그린 생성 + 검증에 걸리는 시간이다.** 그린 생성 자체는 수십 분이지만,
[사전 확인](#사전-확인)의 DB 접속 점검과 백엔드 회신이 끝나 있어야 착수할 수 있다.
당일에 몰아서 하지 말고 **그린을 최소 하루 앞서 띄워 검증 시간을 확보한다.**

#### D-1 이전 — 그린 생성

```bash
aws rds create-blue-green-deployment --profile groble-terraform --region ap-northeast-2 \
  --blue-green-deployment-name groble-prod-mysql-84 \
  --source arn:aws:rds:ap-northeast-2:538827147369:db:groble-prod-mysql \
  --target-engine-version 8.4.11 \
  --target-db-parameter-group-name groble-prod-mysql-84-params
```

> 8.4.11 이 현재 ap-northeast-2 최신이다 (8.4.5~8.4.11 사용 가능).
> 그린은 **8.4 이므로 확장 지원 과금이 붙지 않는다.** 블루는 스위치오버까지 계속 부과된다.

`available` 이 될 때까지 대기 후 **그린에서 직접 검증한다** — 이것이 B/G 를 쓰는 핵심 이유다.

```bash
aws rds describe-blue-green-deployments --profile groble-terraform --region ap-northeast-2 \
  --query 'BlueGreenDeployments[?BlueGreenDeploymentName==`groble-prod-mysql-84`].{Status:Status,Tasks:Tasks}'
```

그린 엔드포인트로 접속해 확인할 것:
- `SELECT VERSION();` → 8.4.x
- `SELECT user, host, plugin FROM mysql.user;` → 인증 플러그인 승계 확인
- 애플리케이션 주요 쿼리 수동 실행 (백엔드가 지정한 네이티브 쿼리 위주)
- `SHOW REPLICA STATUS;` → 블루와의 복제 지연 0 확인

#### 스위치오버 실행

1. **ALB 임계 완화** ([§4](#4-️-반드시-짚어야-할-위험--alb-헬스체크가-태스크를-죽인다) 명령 실행)
2. 복제 지연 0 재확인
3. 스위치오버

```bash
BG=$(aws rds describe-blue-green-deployments --profile groble-terraform --region ap-northeast-2 \
     --query 'BlueGreenDeployments[?BlueGreenDeploymentName==`groble-prod-mysql-84`].BlueGreenDeploymentIdentifier' --output text)
aws rds switchover-blue-green-deployment --profile groble-terraform --region ap-northeast-2 \
  --blue-green-deployment-identifier $BG --switchover-timeout 300
```

RDS 가 쓰기를 차단 → 복제 완결 대기 → **이름을 맞바꾼다.**
그린이 `groble-prod-mysql` 이 되고, 구 인스턴스는 `groble-prod-mysql-old1` 이 된다.
**엔드포인트 DNS 가 동일하므로 ECS 재배포는 필요 없다.**

#### 검증

```bash
# 1. 엔진 버전
aws rds describe-db-instances --profile groble-terraform --region ap-northeast-2 \
  --db-instance-identifier groble-prod-mysql \
  --query 'DBInstances[0].{V:EngineVersion,PG:DBParameterGroups[0],Status:DBInstanceStatus}'

# 2. 앱 정상 여부
curl -sf https://api.groble.im/actuator/health

# 3. 타깃 상태
aws elbv2 describe-target-health --profile groble-terraform --region ap-northeast-2 \
  --target-group-arn $(aws elbv2 describe-target-groups --profile groble-terraform \
    --region ap-northeast-2 --names groble-prod-blue-tg-v2 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

- Grafana 결제 대시보드에서 **R2(결제 활동 부재) / R3(시도 대비 완료 부재)** 가 정상인지 확인
- 실제 결제 1건 e2e 확인
- **ALB 임계를 2로 되돌린다**

#### 확장 지원 과금 정지 확인 (D+2)

Cost Explorer 반영에 1~2일 지연이 있다. 전환 다음날 이후 확인한다.

```bash
# START/END 는 전환일 전후를 감싸도록 직접 채운다 (전환 전 $5.76 → 전환 후 $0 이 보여야 한다)
aws ce get-cost-and-usage --profile groble-terraform --region us-east-1 \
  --time-period Start=<전환일-2일>,End=<전환일+3일> --granularity DAILY --metrics UnblendedCost UsageQuantity \
  --filter '{"And":[{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}},
                    {"Dimensions":{"Key":"USAGE_TYPE","Values":["APN2-ExtendedSupport:Yr1-Yr2:MySQL8.0"]}}]}'
```

**전환 시각 이후 `$0.00 / 0 vCPU-hour` 이면 성공이다.**

---

### Terraform 정합화 — 빠뜨리면 사고가 난다

> ⚠️ **스위치오버 전까지 prod 에서 `terraform apply` 를 실행하지 말 것.**
> 코드가 `engine_version = "8.0"` 인 상태에서 DB 가 8.4 가 되면,
> **Terraform 이 8.0 으로 되돌리려 시도한다.** 스위치오버 직후 아래를 즉시 반영한다.

`modules/infrastructure/rds-mysql/main.tf`:

```hcl
engine_version              = "8.4"          # was "8.0"
allow_major_version_upgrade = true           # 신규
parameter_group_name        = aws_db_parameter_group.mysql_params_84.name
```

`terraform plan` 이 **No changes** 여야 정상이다 (실제 리소스가 이미 그 상태이므로).
차이가 보고되면 그 자리에서 멈추고 원인을 확인한다.

정합화가 끝난 뒤 후속 apply 에서 구 8.0 파라미터그룹 리소스를 제거한다.

### 정리 (D+7, 롤백 창이 닫힌 뒤)

```bash
# 1. B/G 배포 레코드 삭제 (구 인스턴스는 남긴다)
aws rds delete-blue-green-deployment --profile groble-terraform --region ap-northeast-2 \
  --blue-green-deployment-identifier $BG --delete-target false

# 2. 구 인스턴스 삭제 — 삭제 방지 해제가 먼저다
aws rds modify-db-instance --profile groble-terraform --region ap-northeast-2 \
  --db-instance-identifier groble-prod-mysql-old1 --no-deletion-protection --apply-immediately
aws rds delete-db-instance --profile groble-terraform --region ap-northeast-2 \
  --db-instance-identifier groble-prod-mysql-old1 \
  --final-db-snapshot-identifier groble-prod-mysql-80-final
```

**구 인스턴스를 남겨두면 8.0 이므로 확장 지원 과금이 계속된다.** 정리를 잊지 말 것.

---

### 롤백

| 시점 | 방법 | 손실 |
|---|---|---|
| 스위치오버 전 | B/G 배포만 삭제(`--delete-target true`). 블루는 무영향 | 없음 |
| 스위치오버 직후 | `groble-prod-mysql-old1` 로 되돌리기 (rename 또는 `DB_HOST` 변경 후 ECS 재배포) | **전환 후 8.4에 쓰인 데이터** |
| D+7 이후 | 최종 스냅샷 복원 | 복원 시점까지 |

스위치오버 후 롤백은 **데이터 유실을 동반한다.** 결제 데이터가 얽히므로,
문제가 보이면 롤백보다 **정방향 수정(hotfix)** 을 우선 검토한다.
롤백 판단은 전환 후 30분 안에 내린다.

---

## 6. 부수 항목 (이번 범위 밖)

작업 중 확인된 것들이다. 이번 업그레이드와 직접 관계는 없지만 기록해 둔다.

1. **백업 창이 한국 점심시간이다.** `03:00–04:00 UTC` = **12:00–13:00 KST**.
   점검창 `sun:04:00–05:00 UTC` = **일 13:00–14:00 KST** 도 마찬가지다.
   트래픽 실측상 04:00 KST(= 19:00 UTC)가 최저이므로 옮길 가치가 있다.
2. **dev MySQL 컨테이너와 Testcontainers 가 8.0 이다.** prod 만 8.4 가 되면
   **8.4 비호환이 CI 를 통과해 prod 에서 처음 드러난다.** 업그레이드 후 dev 도 8.4 로 맞출 것.
3. **`/actuator/health` 에 liveness/readiness 구분이 없다.** 이번엔 임계 완화로 우회하지만,
   Phase 7(ASG) 에서 노드가 교체될 때 같은 문제가 반복된다. 백엔드에 health group 분리 요청 필요.
4. **✅ 반영 완료 — `CLAUDE.md` 의 RDS SG 서술을 실제에 맞게 고쳤다.** 문서는
   "3306 from Prod/Dev/API Task/Monitoring" 이라고 적었지만, 실제 인그레스는
   **Monitoring · Prod · API Task 3개 SG 뿐이고 Dev 는 없다** (Terraform 코드도 3건뿐이라
   drift 가 아니라 문서 오류였다). 또한 CIDR 인그레스가 없어 **VPN 에서 RDS 로 직접
   접속되지 않는다** — 모니터링 노드 경유 SSH 터널이 필요하다는 점과, native password 계정이라
   **MySQL 9.x 클라이언트로는 접속되지 않는다**는 점을 함께 적어 두었다.
5. **AZ 불일치는 이번에 해소되지 않는다.** 그린도 db_subnet_group 안에서 생성되며 2c 로
   배치될 가능성이 높지만 보장되지 않는다. 전환 후 실제 AZ 를 확인하고, prod EC2(2a)와의
   cross-AZ 문제는 Phase 7 에서 함께 다룬다.
