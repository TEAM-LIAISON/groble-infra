# RDS MySQL 8.0 → 8.4 업그레이드 (확장 지원 과금 중단)

> [이관 절차 목차](../../infra-ha-migration-runbook.md) · Phase 와 독립적인 단발 작업이다. Phase 6(ElastiCache)·Phase 7(prod ASG)과 자원이 겹치지 않는다.

| | |
|---|---|
| **상태** | 📦 **종결 (2026-08-29).** 전환·state 재정렬·구 인스턴스 삭제 모두 완료. 남은 것은 **확장 지원 과금 $0 확인**뿐 (CE 반영 1~2일) — 아래 [실행 기록](#실행-기록-2026-08-29) |
| **목적** | 2026-08-01 부터 자동 부과되기 시작한 **RDS Extended Support 과금(월 $178.56)을 멈춘다** |
| **사용자 영향** | Blue/Green 전환 시 **쓰기 차단 약 1분**. 그 외 무중단 |
| **되돌리기** | 전환 후 구 인스턴스(`-old1`)가 남으므로 **엔드포인트 되돌리기 가능**. 단 전환 후 쓰기분은 유실 |
| **일정** | 날짜 미정 — 담당자가 지정한다. **조건 2개: ① 앱 배포가 없는 날 ② 04:10~04:50 KST**(백엔드 요청) |

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
| MySQL Connector/J | **9.7.0** (백엔드 실측, 2026-08-28) | ✅ 8.4 지원 |
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

> **가설이 아니라 이미 일어난 일이다.** 2026-07-26 RDS 유지보수로 DB 가 4분 중단됐을 때,
> **앱 프로세스는 계속 살아 있었고 태스크를 죽인 것은 ALB 헬스체크였다** (백엔드 회신, 2026-08-28).
> 이번 전환은 쓰기만 막히므로 그때보다 조건이 좋지만, 완화를 빠뜨리면 같은 일이 반복된다.

**백엔드가 이 완화를 전환 전에 확정해 달라고 명시적으로 요청했다** — HikariCP 자동 복구의 전제 조건이다.

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

> ⚠️ **활성 타깃그룹은 배포 때마다 blue ↔ green 으로 뒤바뀐다.** CodeDeploy 가 그렇게 동작한다
> (2026-08-26 에는 blue, 8-28 에는 green 이 활성이었다). **위 명령이 양쪽을 모두 도는 이유다** —
> 한쪽만 바꾸면 하필 그쪽이 비활성일 수 있다. 전환 직전에 어느 쪽이 타깃을 쥐고 있는지 확인할 것:
>
> ```bash
> aws elbv2 describe-target-health --profile groble-terraform --region ap-northeast-2 \
>   --target-group-arn <각 TG ARN> --query 'length(TargetHealthDescriptions)'
> ```

전환 완료 검증 후 `--unhealthy-threshold-count 2` 로 되돌린다.
**되돌리지 않으면 Terraform 이 다음 apply 에서 되돌리며 drift 를 보고한다.**

> ⚠️ **순서를 지킬 것.** 이 완화는 Terraform 이 관리하는 타깃그룹을 CLI 로 건드리는 것이라,
> **완화 적용 후 스위치오버 전까지 `terraform apply` 를 실행하면 임계가 2로 되돌아간다.**
> ④⑤ apply 는 **완화보다 먼저** 끝내 둘 것.

---

## 5. 절차

### 사전 확인

**모두 끝나기 전에는 D-Day 를 잡지 않는다.**

| # | 항목 | 상태 |
|---|---|---|
| ① | 인증 플러그인 | ✅ 통과 — RDS 8.4 가 native password 를 켠 채 고정한다 |
| ② | 스키마 (MyISAM · utf8mb3) | ✅ 통과 — 106테이블 전부 InnoDB, utf8mb3 없음 |
| ③ | 백엔드 회신 3건 ([요청서](../../handoff/closed/rds-mysql-84-compatibility.md)) | ✅ 통과 — 3건 모두 진행 가능, 조건 3개 첨부 |
| ④⑤ | Terraform 사전 변경분 | ✅ **apply 완료 (2026-08-28)** — `binlog_format=ROW` in-sync, 8.4 PG 생성됨 |

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

#### ③ 백엔드 회신 — ✅ **회신 완료 (2026-08-28). 3건 모두 진행 가능**

요청서: [`docs/handoff/rds-mysql-84-compatibility.md`](../../handoff/closed/rds-mysql-84-compatibility.md)

| # | 질문 | 회신 |
|---|---|---|
| Q1 | Connector/J 해석 버전 | **9.7.0** (실측). 조치 불필요. Flyway 11.7.2 도 8.4 지원 확인 |
| Q2 | 직접 작성 SQL | **문제 없음.** 지목한 9개 파일 40군데 전수 + 저장소 전체 검색. **단 그린에서 실쿼리 재검증을 원함** |
| Q3 | 1분 쓰기 차단 | **점검 공지 없이 진행 가능.** 단 조건 3가지 (아래) |

**Q2 — 신규 예약어가 확정됐다.** 8.0 → 8.4 사이 새로 예약어가 된 단어는 **`QUALIFY`, `TABLESAMPLE` 2개**다.
`MANUAL` 과 `PARALLEL` 은 **8.4.0~8.4.10 에서만 예약어였고 8.4.11 부터 풀렸다.**

> ✅ **타깃을 `8.4.11` 로 잡은 것이 결과적으로 옳았다.** 8.4.10 이하로 내려가면 예약어가 2개 더 늘어난다.
> 코드에 네 단어 모두 없어 결론은 같지만, **버전을 낮출 이유가 없다.**

**Q3 — 백엔드가 건 조건 3가지.** 이것이 이번 회신에서 실행에 직접 영향을 주는 부분이다.

| 조건 | 누가 | 반영 위치 |
|---|---|---|
| ① 헬스체크 임시 완화를 **전환 전에 확정** | 인프라 | [§4](#4-️-반드시-짚어야-할-위험--alb-헬스체크가-태스크를-죽인다) |
| ② 전환 시각 **04:10~04:50 KST** (정각 배치 회피) | 인프라 | [D-Day](#d-day--스위치오버) |
| ③ **앱 배포가 없는 날**로 잡을 것 | 인프라 | 아래 |
| ④ 전환 직후 승인 불명 대기열·알림 채널 확인 | 백엔드 | [검증](#검증) |

**날짜 조건 — 앱 배포가 없는 날.** DB 전환과 앱 배포가 겹치면 문제 발생 시 원인을 가릴 수 없다.
인증 방식 변경을 별건으로 뺀 것과 같은 이유다.

**HikariCP 는 자동 복구된다** — 재시작 불필요. 커넥션 대여 시 유효성 검증(validation-timeout 5초)을
하고 죽은 커넥션을 버린다. 차단 중 쓰기는 최대 30초 대기 후 실패하고, 차단이 풀리면 1분 안에 정상화된다.

**결제 정합성은 자동 복구 경로가 이미 있다.** 우려했던 "Redis 예약은 잡혔는데 DB 기록 실패" 상태는
`stock:reserved:*` TTL 30분 + 결제 실패 시 즉시 해제 로직으로 **늦어도 30분 안에 자동 해소**되며,
틀어지는 방향도 안전하다(재고를 잠깐 더 잡을 뿐 초과 판매로 가지 않는다). 더 위험한
"PG 승인은 났는데 DB 기록 실패" 건은 승인 불명 마커 + 어드민 대기열·확정 API 가 이미 운영에 있다.

**백엔드가 함께 처리하는 것** — Testcontainers `mysql:8.0` → `mysql:8.4` (별도 PR, 이번 전환의 선행 조건 아님) ·
멤버십 청구 배치 주기를 prod 부팅 로그(`event=scheduled_inventory`)로 확정.

#### ④⑤ Terraform 사전 변경분 — ✅ **apply 완료 (2026-08-28)**

브랜치 **`feat/rds-mysql-84-upgrade`** 에 있다. 두 가지가 들어 있다.

| 변경 | 파일 | 이유 |
|---|---|---|
| 기존 8.0 그룹에 `binlog_format = ROW` | `modules/infrastructure/rds-mysql/main.tf` | B/G 전제조건. 동적 파라미터라 **재부팅 불필요** |
| `aws_db_parameter_group.mysql_params_84` 신설 (family `mysql8.4`) | 〃 | family 는 변경 불가 속성이라 기존 그룹을 고칠 수 없다. 같은 이름으로 replace 하면 destroy/create 가 이름 충돌로 맞물린다 |
| 출력 `mysql_84_parameter_group_name` | `modules/infrastructure/rds-mysql/outputs.tf`, `environments/prod/main.tf` | 아래 B/G 명령에 그대로 넘기기 위해 |

> ⚠️ **최초 판단은 틀렸고 2026-08-28 에 바로잡았다.** 여기 원래 "`innodb_buffer_pool_size` 는
> 8.0 에서도 실질 no-op 이니 8.4 그룹으로 옮기지 않는다"고 적혀 있었다. **8.0 기준으로는 맞지만
> 8.4 에서는 정반대 결과가 나온다** — 아래 [파라미터 정합](#파라미터-정합--84-기본값이-조용히-바꾸는-것) 참조.

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

**적용 결과 (2026-08-28)**

```
aws_db_parameter_group.mysql_params_84   생성 완료  (family mysql8.4)
aws_db_parameter_group.mysql_params      binlog_format = ROW  → in-sync
aws_db_instance.mysql                    backup_window 03:00-04:00 → 18:00-19:00 UTC
terraform plan                           No changes. (드리프트 없음)
```

적용 후 `api.groble.im/actuator/health` **HTTP 200**, prod 타깃 healthy 확인.

> **중간에 한 번 실패했다.** `binlog_format` 이 `immediate` 로 적용되는 동안 인스턴스가
> `modifying` 상태가 되어, 같은 apply 안의 인스턴스 수정이 `InvalidDBInstanceState` 로 거부됐다.
> `aws rds wait db-instance-available` 로 기다렸다가 재실행해 해결했다.
> **파라미터그룹 변경과 인스턴스 속성 변경을 한 apply 에 같이 넣으면 재현된다.**

**함께 처리한 것 — 백업창·점검창을 KST 새벽으로 옮겼다** ([부수 항목 1](#6-부수-항목-이번-범위-밖) 해소).

| | 이전 (UTC) | 이후 (UTC) | KST |
|---|---|---|---|
| 백업창 | `03:00-04:00` | **`18:00-19:00`** | 03:00~04:00 |
| 점검창 | `sun:04:00-sun:05:00` | **`sun:19:00-sun:20:00`** | 월 04:00~05:00 |

점검창은 콘솔에서 먼저 바뀌어 있던 것을 코드에 맞췄다(드리프트 해소). 백업창은
**전환 창(04:10~04:50 KST)과 겹치지 않도록 04:00 KST 에 끝나게** 잡았다 — RDS 는 백업창과
점검창이 중첩하면 수정을 거부하므로 둘을 인접시키되 겹치지 않게 두었다.

> ⚠️ **이 브랜치에는 스위치오버 이후 반영할 변경(`engine_version = "8.4"` 등)은 들어 있지 않다.**
> 미리 넣으면 apply 시 Terraform 이 **in-place 메이저 업그레이드를 시도**하기 때문이다.
> 해당 변경은 아래 [Terraform 정합화](#terraform-정합화--빠뜨리면-사고가-난다) 에 명세만 해 뒀고,
> **스위치오버가 끝난 뒤에 별도 커밋으로 만든다.**

---

### D-Day — 스위치오버

> **날짜는 담당자가 지정한다.** 아래 D-n 은 D-Day 기준 상대 일자일 뿐이다.

**날짜 조건 — 앱 배포가 없는 날.** 백엔드 요청이다. DB 전환과 앱 배포가 겹치면 문제 발생 시
원인을 가릴 수 없다.

**시각 — `04:10 ~ 04:50 KST` 로 확정한다.**

두 근거가 겹친 구간이다.

1. **트래픽** — 최근 14일 ALB RequestCount 실측상 04~06시가 최저다.
   04시 1,666 req/h 로 피크(16시) 5,036 req/h 의 **1/3 수준**. 가장 나쁜 선택은 16시대다.
2. **배치 회피** — 백엔드가 제공한 운영 배치 시각표다.

| 배치 | 실행 시각 (KST) | 04:10~04:50 과 충돌? |
|---|---|---|
| 상품 정기결제 청구 | 매일 09:00 | 없음 |
| 구독 유예기간 만료 처리 | 00:00 · 06:00 · 12:00 · 18:00 | 없음 (06:00 회피) |
| 멤버십 만료류 처리 | **매시 정각** | 없음 (04:00·05:00 회피) |
| 멤버십 청구 폴링 | 5분 주기 | 겹치나 **무해** — 다음 주기에 자동 따라잡음 |
| 상품 판매종료 처리 | 5분 주기 | 〃 |

**정각을 피하면 실패·재시도 소음 자체가 생기지 않는다.** 그래서 04:00 정각이 아니라 **04:10 이후**다.

> 멤버십 청구 폴링 주기(5분)는 코드 기본값 기준이며 SSM 재정의 가능성이 남아 있다.
> **백엔드가 전환 전에 prod 부팅 로그(`event=scheduled_inventory`)로 확정**하기로 했다.

**최소 선행 시간은 그린 생성 + 검증이다.** 그린 생성 자체는 수십 분이지만
**백엔드가 그린에서 실쿼리를 돌려보겠다고 했으므로**, 당일에 몰아서 하지 말고
**최소 하루 앞서 띄워 검증 시간을 확보한다.**

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

**백엔드에 그린 접속 정보를 넘긴다.** 회신에서 "어드민 통계 쿼리 위주로 실서버에서 돌려
문법과 함께 성능(옵티마이저 변화)까지 확인하겠다"고 요청했다.

> ⚠️ **그린도 blue 와 같은 SG 를 쓰므로 VPN 에서 직접 닿지 않는다.** CIDR 인그레스가 없어
> 3306 이 거부된다. 백엔드에 넘겨야 하는 것은 엔드포인트만이 아니라 **접속 경로 전체**다 —
> ① VPN 연결 ② 모니터링 노드 SSH 키 ③ 아래 터널 명령 ④ 계정 정보.
> **`groble_root` 는 native password 라 MySQL 9.x 클라이언트로는 접속되지 않는다는 점**도 함께 알린다
> (8.x 클라이언트 또는 `pymysql`).

```bash
# 그린 엔드포인트 확인
aws rds describe-db-instances --profile groble-terraform --region ap-northeast-2 \
  --query 'DBInstances[?contains(DBInstanceIdentifier,`green`)].{ID:DBInstanceIdentifier,EP:Endpoint.Address,V:EngineVersion}'

# 터널 (모니터링 노드 경유)
ssh -f -N -L 13306:<그린 엔드포인트>:3306 -i <key>.pem ubuntu@10.0.1.193
```

```bash
aws rds describe-blue-green-deployments --profile groble-terraform --region ap-northeast-2 \
  --query 'BlueGreenDeployments[?BlueGreenDeploymentName==`groble-prod-mysql-84`].{Status:Status,Tasks:Tasks}'
```

그린 엔드포인트로 접속해 확인할 것:
- `SELECT VERSION();` → 8.4.x
- `SELECT user, host, plugin FROM mysql.user;` → 인증 플러그인 승계 확인
- 애플리케이션 주요 쿼리 수동 실행 (백엔드가 지정한 네이티브 쿼리 위주)
- `SHOW REPLICA STATUS;` → 블루와의 복제 지연 0 확인

**생성 결과 (2026-08-28)**

| | 값 |
|---|---|
| B/G 배포 ID | `bgd-j3rtbaneibatpqlc` |
| 그린 인스턴스 | `groble-prod-mysql-green-ftzmon` |
| 엔진 | **8.4.11** (`DB_ENGINE_VERSION_UPGRADE: COMPLETED`) |
| 파라미터그룹 | `groble-prod-mysql-84-params` (in-sync) |
| AZ | **ap-northeast-2c** — 블루와 동일. cross-AZ 신규 발생 없음 |
| 복제 | `replicating` / `Normal: true`, ReplicaLag 0초 |
| 블루 영향 | 없음 — 생성 내내 `available`, 헬스체크 200, 여유 메모리 27~37 MiB (평시 범위 내) |

백엔드 전달용 접속 안내: [`docs/handoff/rds-84-green-access.md`](../../handoff/closed/rds-84-green-access.md)

#### 파라미터 정합 — 8.4 기본값이 조용히 바꾸는 것

**백엔드가 블루/그린 파라미터를 전수 비교해 3건의 차이를 제보했고(2026-08-28), 확인 결과 4건이었다.**
원인은 인스턴스 클래스가 아니다 — 양쪽 모두 `db.t3.micro` 다. **RDS 의 8.0 / 8.4 기본값 정책이 다르다.**

| 파라미터 | mysql8.0 기본 | mysql8.4 기본 |
|---|---|---|
| `innodb_dedicated_server` | 없음 (= 0) | **1 (ON)** |
| `innodb_buffer_pool_size` | `{DBInstanceClassMemory*3/4}` | **없음** |
| `innodb_redo_log_capacity` | `2147483648` | **없음** |
| `log_output` | `TABLE` | **없음** |

8.4 부터 AWS 가 `innodb_dedicated_server` 를 켜고 크기 기본값을 없앴다. 그러면 MySQL 이 감지 메모리로
자동 계산하는데, **1 GiB 인스턴스에서는 "1GB 미만" 구간의 최솟값이 잡힌다.**

| 변수 | blue | green (수정 전) | green (수정 후) |
|---|---|---|---|
| `innodb_buffer_pool_size` | 256 MiB | **128 MiB** | 256 MiB ✅ |
| `innodb_redo_log_capacity` | 2048 MiB | **1024 MiB** | 2048 MiB ✅ |
| `innodb_dedicated_server` | 0 | 1 | 0 ✅ |
| `log_output` | TABLE | FILE | TABLE ✅ |

**버전 업그레이드는 like-for-like 여야 한다.** 성능 특성을 같이 바꾸면 전환 후 문제가 생겼을 때
8.4 탓인지 버퍼풀 탓인지 갈리지 않는다. 튜닝은 전환이 끝난 뒤 측정해서 별도로 한다.

> `innodb_dedicated_server` 가 1 이면 MySQL 이 buffer pool·redo 를 자동 설정하고 **명시값을 무시한다.**
> 반드시 0 으로 꺼야 나머지 두 값이 먹는다. static 파라미터라 **그린 재부팅이 필요**하다
> (트래픽을 받지 않으므로 자유롭다. 재부팅 후 복제는 스스로 재개했고 데이터도 계속 일치했다).

**맞출 수 없는 것이 하나 있다 — `log_error_suppression_list`** (blue = `MY-013360`).
RDS 가 이 파라미터를 **설정 가능 항목으로 노출하지 않는다**(8.0·8.4 양쪽 그룹 어디에도 없음).
블루의 값은 RDS 가 내부적으로 넣은 것이다. 8.4 에서는 해당 경고(`mysql_native_password` deprecated)가
에러 로그에 남지만 **기능 영향은 없다.**

**그 밖의 차이는 전부 MySQL 8.4 상류 기본값 변경이다** (글로벌 변수 606개 전수 diff, 실질 차이 19건).
쿼리 플랜 관점에서 중요한 것 두 가지:

- **`optimizer_switch` 는 기존 플래그 값이 전부 동일하다.** 유일한 차이는 8.4 신규 플래그
  `hash_set_operations=on` 뿐이다 — **기존 쿼리의 실행계획이 이것 때문에 바뀌지는 않는다**
- ⚠️ **`innodb_io_capacity` 200 → 10000, `innodb_io_capacity_max` 2000 → 20000.**
  gp2 20GB 는 baseline 60 IOPS 라 실제 성능과 크게 어긋난다. InnoDB 가 과하게 플러시해
  버스트 크레딧을 소진할 수 있다. **전환 후 `BurstBalance` 를 관찰할 것** (이번엔 손대지 않는다 —
  8.4 기본값을 존중하고, 문제가 보이면 측정해서 조정한다)

**데이터 일치 실측 (2026-08-28, 양쪽 직접 접속 비교)**

| 항목 | blue (8.0.45) | green (8.4.11) |
|---|---:|---:|
| 테이블 수 | 106 | 106 |
| **전체 행수 합계** | **510,690** | **510,690** |
| `mysql.user` 계정 | 7 | 7 |

복제가 실제로 도는 것도 확인했다 — 비교 도중 `content_view_logs` 가 95,829 → 95,830 으로
늘었고 **양쪽이 함께 늘었다.**

**그린 쓰기는 서버가 막는다** — `read_only = 1` 이고 `groble_root` 에 `SUPER` 가 없다.
백엔드가 실수로 써도 데이터가 어긋나지 않는다.

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

#### 스위치오버가 실제로 하는 일 (오해 방지)

**블루는 업그레이드되지 않는다.** 8.4 전환은 그린을 만들 때 이미 끝났고
(`DB_ENGINE_VERSION_UPGRADE: COMPLETED`), 스위치오버는 **이미 8.4 인 DB 로 갈아타는 것**이다.
그래서 1분이면 된다 — 업그레이드 작업이 그 안에 없다.

RDS 가 하는 일의 순서다.

```
① 양쪽 환경의 기존 커넥션을 전부 끊고 새 커넥션도 막는다
② 블루의 쓰기를 중단시킨다
③ 그린이 남은 복제분을 따라잡을 때까지 기다린다
④ 이름을 맞바꾼다  (블루 → -old1, 그린 → groble-prod-mysql)
⑤ 그린의 read_only 해제, 복제 연결 끊기
⑥ 커넥션 수락 재개
```

**앱이 이 구간에 보는 오류는 `1290 (HY000): The MySQL server is running with the
--read-only option` 이다.** 결제 실패 로그에서 이 문자열을 찾으면 전환 구간의 실패로 식별된다.

> ⚠️ **"앱을 그린 엔드포인트로 재배포한다"는 접근은 틀렸고 위험하다.**
> ① 전환 전에는 그린이 읽기 전용이라 쓰기가 전부 실패하고,
> ② 전환 후에는 **그 이름이 구 DB(`-old1`)에 붙는다** — 앱이 옛 DB 를 계속 쓰게 되고
> D+7 에 구 인스턴스를 지우면 앱이 죽는다.
> 그린 엔드포인트는 **백엔드 검증용 임시 주소**이며 전환과 함께 사라진다.

**🔴 JVM DNS 캐시 — 실제로 발생했다 (2026-08-29)**

RDS 가 커넥션을 끊어 주므로 앱은 재연결하고, 그때 DNS 가 그린을 가리킨다.
**단 JVM 이 DNS 를 캐시하면 재연결이 옛 IP(= `-old1`)로 갈 수 있다.**

- 보안 관리자가 설정돼 있지 않은 JDK 는 성공한 조회를 **30초** 캐시한다(기본값). 이 경우 문제없다
- `networkaddress.cache.ttl` 을 크게 잡아 두었다면 그만큼 옛 DB 를 붙잡는다

**전환 후 검증에서 "앱이 실제로 8.4 에 붙었는지"를 반드시 확인할 것.** 헬스체크 200 만으로는
구 DB 에 붙어 있어도 통과한다 — 아래 검증의 `SELECT VERSION()` 확인이 그래서 있다.

#### 검증

```bash
# 1. 엔진 버전
aws rds describe-db-instances --profile groble-terraform --region ap-northeast-2 \
  --db-instance-identifier groble-prod-mysql \
  --query 'DBInstances[0].{V:EngineVersion,PG:DBParameterGroups[0],Status:DBInstanceStatus}'

# 2. 앱 정상 여부
curl -sf https://api.groble.im/actuator/health

# 2-1. ⚠️ 앱이 정말 8.4 에 붙었는지 — 헬스체크 200 만으로는 알 수 없다
#      (JVM DNS 캐시로 구 DB 에 붙어 있어도 200 이 나온다)
#      백엔드에 요청하거나, 그린에서 현재 접속 목록을 확인한다:
#        SELECT VERSION();                         -- 8.4.11 이어야 한다
#        SELECT COUNT(*) FROM information_schema.processlist
#         WHERE user = 'groble_root';             -- 앱 커넥션이 여기 잡혀야 한다

# 3. 타깃 상태
aws elbv2 describe-target-health --profile groble-terraform --region ap-northeast-2 \
  --target-group-arn $(aws elbv2 describe-target-groups --profile groble-terraform \
    --region ap-northeast-2 --names groble-prod-blue-tg-v2 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

- Grafana 결제 대시보드에서 **R2(결제 활동 부재) / R3(시도 대비 완료 부재)** 가 정상인지 확인
- 실제 결제 1건 e2e 확인
- **ALB 임계를 2로 되돌린다**

**백엔드 쪽 체크리스트** (회신에서 자체 액션으로 제시한 것)

- [x] 전환 직후 — **승인 불명 대기열 조회**, 결제 알림 채널 확인, 에러율·슬로우 쿼리 대시보드 확인
      → **이상 없음** (2026-08-30 회신)
- [x] 전환 후 첫 **09:00 — 상품 정기결제 청구 배치** 정상 수행 확인
      → **정상 수행** (2026-08-30 회신)

> ✅ **두 확인 모두 이상 없음으로 회신받았다 (2026-08-30).** 02:19:30~02:27 의 쓰기 실패
> 구간이 결제 데이터에 피해를 남기지 않았다는 뜻이며, 이것으로 전환이 진짜 끝났다.
>
> ⚠️ 다만 **구 인스턴스는 이 확인보다 먼저 삭제됐다** (2026-08-29). 원래 이 문서는
> "09:00 배치 확인 전에 롤백 창(D+7)을 닫지 말 것"이라고 적고 있었는데, 실제로는
> 확인 전에 닫혔다. 결과적으로 문제가 없었지만 **순서는 계획과 달랐다.**
> 남은 복구 수단은 최종 스냅샷 `groble-prod-mysql-80-final`(8.0.45) 하나다.

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

### Terraform 정합화 — **state 재연결이 필요하다. 코드 수정만으로는 안 된다**

> ⚠️ **이 절은 2026-08-28 에 전면 수정됐다.** 이전 판은 "`engine_version` 을 8.4 로 고치면
> `plan` 이 No changes" 라고 적었는데 **틀렸다.** 아래가 이유다.

#### 왜 코드 수정만으로는 안 되나

**Terraform state 는 이 인스턴스를 `identifier` 가 아니라 `DbiResourceId` 로 추적한다.**

```
state 상의 리소스 ID : db-WM4VKRGNLYVHSHUBNSEJJM3AZ4   ← 이것으로 추적한다
identifier           : groble-prod-mysql
```

스위치오버는 **이름표만 맞바꾸고 `DbiResourceId` 는 인스턴스마다 고유하다.** 그래서 전환 직후:

| 실제 | Terraform 이 보는 것 |
|---|---|
| `groble-prod-mysql` = 신규 8.4 (새 DbiResourceId) — **앱이 쓰는 DB** | 안 보임 |
| `groble-prod-mysql-old1` = 구 8.0 (`db-WM4VKRG…`) | **여기를 계속 관리** |

**즉 Terraform 이 구 인스턴스를 붙잡고 있다.** 이 상태로 `-old1` 을 지우면 state 가 고아가 되고,
운영 DB 는 Terraform 관리 밖으로 빠진다.

> `aws_db_instance` 에는 `blue_green_update { enabled = true }` 블록이 있어 Terraform 이
> 전 과정을 대신 수행하고 state 도 정리해 준다. **다만 생성→전환→구 인스턴스 삭제를
> 한 apply 안에서 끝내 중단점이 없다** — 백엔드 실쿼리 검증과 04:10~04:50 전환 창을
> 둘 다 지킬 수 없어 채택하지 않았다. (독립 리소스 `aws_rds_blue_green_deployment` 는 없다)

#### 순서 — 스위치오버 직후 즉시

**1. state 에서 구 인스턴스를 떼어낸다**

```bash
cd environments/prod
terraform state rm module.rds_mysql.aws_db_instance.mysql
```

> `prevent_destroy = true` 는 `state rm` 을 막지 않는다 (destroy 가 아니다). 리소스는 그대로 살아 있다.

**2. 코드를 8.4 로 고친다** — `modules/infrastructure/rds-mysql/main.tf`

```hcl
engine_version              = "8.4.11"      # ⚠️ 마이너까지 정확히. was "8.0"
allow_major_version_upgrade = true          # 신규
parameter_group_name        = aws_db_parameter_group.mysql_params_84.name
```

> ⛔ **`"8.4"` 로 적으면 apply 가 실패한다.** AWS 가 이를 **패밀리 기본값(8.4.9)** 으로 해석해
> 8.4.11 → 8.4.9 **다운그레이드를 시도**한다. 2026-08-29 실제로 겪었다:
>
> ```
> InvalidParameterCombination: Cannot upgrade mysql from 8.4.11 to 8.4.9
> ```
>
> 8.0 시절 `"8.0"` 표기가 통했던 것은 **패밀리 기본값이 마침 실제 버전과 같았기 때문일 뿐**이다.
> `auto_minor_version_upgrade` 가 켜져 있어 RDS 가 점검창에 마이너를 올리면 plan 에 드리프트로
> 뜬다. 그때 이 값을 실제 버전으로 올린다 — **드리프트가 보이는 편이 조용히 어긋나는 것보다 낫다.**

**3. 신규 인스턴스를 import 한다** — **identifier 로 넣는다** (resource id 아님)

```bash
terraform import module.rds_mysql.aws_db_instance.mysql groble-prod-mysql
```

> ✅ **검증 완료 (2026-08-28).** 별도 작업공간에서 `import` 블록으로 확인한 결과,
> provider 5.100.0 은 **identifier 를 받아 `resource_id` 로 해석**한다
> (`groble-prod-mysql` → `db-WM4VKRG…`). 전환 후에 실행하면 새 인스턴스가 잡힌다.

**4. `terraform plan` 으로 확인한다**

```bash
terraform plan
```

**예상되는 유일한 차이는 `password` 다.** RDS API 가 마스터 비밀번호를 돌려주지 않아
import 직후 state 에 값이 없고, 코드에는 `var.mysql_root_password` 가 있어 diff 가 뜬다.
**같은 값을 다시 넣는 것이라 무해하며**(RDS 는 마스터 비밀번호 변경을 무중단 즉시 적용한다)
그대로 apply 해서 해소한다.

**그 밖의 차이가 보이면 그 자리에서 멈추고 원인을 확인한다.** 특히
`identifier` 나 `engine_version` 에 차이가 있으면 잘못된 인스턴스를 잡은 것이다.

#### 하지 말 것

- ⛔ **스위치오버 전에 `terraform apply` 를 실행하지 말 것.** 코드가 `engine_version = "8.0"`
  인 상태라 8.4 로 바뀐 DB 를 되돌리려 한다
- ⛔ **1~3 을 마치기 전에 `terraform apply` 를 실행하지 말 것.** state 가 `-old1` 을 가리키는
  동안 apply 하면 **구 인스턴스의 이름을 `groble-prod-mysql` 로 되돌리려 시도**한다
- ⛔ **정합화 전에 `-old1` 을 삭제하지 말 것.** state 가 고아가 된다

정합화가 끝난 뒤 후속 apply 에서 구 8.0 파라미터그룹 리소스를 제거한다.

### 정리 — ✅ **완료 (2026-08-29 16:09 KST)**

> ⛔ **[Terraform 정합화](#terraform-정합화--state-재연결이-필요하다-코드-수정만으로는-안-된다)가
> 끝난 뒤에만 실행한다.** state 가 아직 `-old1` 을 가리키는 상태에서 지우면 state 가 고아가 된다.

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

## 실행 기록 (2026-08-29)

**전환은 성공했다. 다만 계획대로 흘러가지 않은 구간이 있었고, 그게 이 문서에서 가장 중요한 부분이다.**

### 타임라인

| 시각 (KST) | 일 |
|---|---|
| 02:16 | 사전 점검 — B/G `AVAILABLE`, 복제 지연 0, 양쪽 `available` |
| 02:17 | ALB 헬스체크 임계 완화 (2 → 5, 양쪽 TG) |
| 02:18:55 | **스위치오버 실행** |
| 02:19:20 | 앱 헬스체크 1회 실패 (쓰기 차단 구간) |
| 02:19:30 | **스위치오버 완료 — 약 35초** |
| 02:22 | ⚠️ 앱이 **구 DB 에 재연결**된 것을 발견 (아래) |
| 02:23:54 | 백엔드가 ECS 태스크 재배포 |
| 02:27 | ALB 트래픽이 신 태스크로 전환 |
| 02:28:58 | 구 태스크 종료 — 구 DB 커넥션 소멸 |
| 이후 | ALB 임계 원복 · state 재정렬 |

> **전환 창(04:10~04:50)을 지키지 않고 02:18 에 실행했다.** 담당자 판단이었고 백엔드도 인지한
> 상태였다. 03:00 정각 배치까지 44분 여유가 있어 배치 충돌은 없었다.

### 🔴 사고 1 — 앱이 구 DB 에 붙어 쓰기가 막혔다 (약 7~8분)

스위치오버 직후 앱 커넥션이 **구 DB(`-old1`, `read_only=1`)로 재연결**됐다.

```
신 DB 8.4  ← 앱 커넥션  1개
구 DB 8.0  ← 앱 커넥션 10개   (id 235246~255, 재연결된 새 커넥션)
```

- DNS 는 정상이었다 (`groble-prod-mysql` → 10.0.12.96 = 신규)
- ~~**JVM 이 구 IP 를 캐시**한 것이다~~ → **오진이었다. 아래 정정 참조**
- **헬스체크는 200 이었다.** 조회는 구 DB 에서도 되기 때문이다 —
  **헬스체크만 보고 전환 성공을 판정하면 안 된다는 근거가 이것이다**
- 조회·로그인은 정상, **결제·저장 등 쓰기만 실패**

**해결** — 백엔드가 ECS 태스크를 재배포했다. 새 JVM 이 뜨면서 DNS 를 다시 조회했다.
CodeDeploy 블루/그린이라 태스크가 잠시 2개 공존했고(신 `10.0.11.87` → 신 DB /
구 `10.0.11.127` → 구 DB), 구 태스크가 종료되면서 정리됐다.

#### ⚠️ 원인 정정 — DNS 캐시가 아니라 **커넥션 풀 수명**이다 (2026-08-30)

인프라가 이 사고를 "JVM DNS 캐시"로 진단하고 백엔드에 TTL 단축을 요청했으나,
[회신](../../handoff/closed/jvm-dns-cache.md)에서 정정됐다. **TTL 을 낮춰도 같은 사고는 재발한다.**

| | |
|---|---|
| **DNS TTL 이 관여하는 시점** | **새 연결을 맺는 순간뿐이다.** 이미 맺어진 TCP 커넥션은 DNS 를 다시 조회하지 않는다 — TTL 이 1초여도 상대가 끊거나 풀이 버릴 때까지 그 IP 에 남는다 |
| **실제 원인** | HikariCP 의 `max-lifetime` **30분**. 풀 크기가 10 이고, 관측된 "커넥션 10개"와 일치한다 |
| **왜 풀이 안 버렸나** | 구 DB 는 **읽기 전용**이라 쓰기만 실패했는데, 풀의 유효성 검사는 읽기 전용 커넥션도 정상으로 판정한다. 헬스체크가 200 이었던 것도 같은 이유다 |
| **재배포 없이 뒀다면** | **최대 30분 뒤 수명 순환으로 회복**됐을 사건이다. "TTL 이 짧았다면 60초 만에 회복"은 성립하지 않는다 |

> 참고로 JVM 의 실제 TTL 은 **성공 30초 / 실패 10초**(JDK 17 기본값)였다. 무기한이 아니었다.
> `-1`(무기한)은 SecurityManager 가 설치된 JVM 에만 해당하는데 이 앱은 쓰지 않는다.

**다음에 할 일** (정정 후)

1. **계획된 DB 전환 절차에 "전환 직후 앱 재기동"을 명시한다.** 8/29 에 실제로 해소한 방법이고
   비용이 가장 싸다. 이것이 당장 쓸 수 있는 대응이다
2. **근본 해법은 드라이버 쪽이다** — AWS `aws-advanced-jdbc-wrapper` 는 블루/그린 전환과
   페일오버를 인지해 풀을 스스로 갈아탄다. 도입 검토는 백엔드가 별건으로 진행한다
3. ~~JVM `networkaddress.cache.ttl` 단축 요청~~ — **이 사고와 무관하다.** 별개 이유
   (모니터링 노드 교체)로는 유효하며 명시 설정 PR 이 진행 중이다

### 🔴 사고 2 — `engine_version = "8.4"` 로 apply 가 실패했다

state 재정렬 중 `terraform apply` 가 이렇게 실패했다.

```
InvalidParameterCombination: Cannot upgrade mysql from 8.4.11 to 8.4.9
```

AWS 가 `"8.4"` 를 **패밀리 기본값(8.4.9)** 으로 해석해 다운그레이드를 시도했다.
`"8.4.11"` 로 정확히 고정해 해결했다. 상세는
[Terraform 정합화](#terraform-정합화--state-재연결이-필요하다-코드-수정만으로는-안-된다) 참조.

> 이 실패로 태그 갱신은 적용됐고 `ModifyDBInstance` 만 거부됐다. 인스턴스는 무영향이었다.

### 최종 확인

```
groble-prod-mysql        8.4.11  available  PG: 8.4-params (in-sync)
groble-prod-mysql-old1   8.0.45  available  (롤백용, D+7 삭제 대상)

앱 커넥션    신 DB 10개 / 구 DB 0개
헬스체크     200, prod 타깃 healthy
ALB 임계     2 (원복 완료)
terraform    No changes
state id     db-CY5YZ... (구 db-WM4VK... 에서 교체됨)
```

### 정리 — 완료 (2026-08-29 16:09 KST)

백엔드 회신을 받고 예정(8/31)보다 이틀 앞당겨 정리했다.

**삭제 전 확인한 것**

| 점검 | 결과 |
|---|---|
| 구 DB 커넥션 (최근 6시간) | **0** — 30분 간격 12회 전부 0 |
| RDS 알람 6개의 감시 대상 | 전부 `groble-prod-mysql`(신규), 전부 `OK`. 구 인스턴스를 보는 알람 없음 |
| Terraform state | 구 인스턴스 참조 없음 (전환 직후 재정렬 완료) |
| 운영 DB 삭제 방지 | `True` 유지 |

> **구 DB 는 사고 구간 복구에 쓸 수 없다.** 02:19:30~02:27 의 실패한 쓰기는 구 DB 가
> `read_only=1` 이었으므로 **거부된 것이지 구 DB 로 흘러간 것이 아니다.** 구 DB 는
> 02:19:30 시점에 얼어붙은 사본일 뿐이고, 그 값은 최종 스냅샷이 대신한다.

**실행 순서** (이 순서를 지킬 것)

```
① B/G 배포 레코드 삭제   --no-delete-target   ← 플래그명 주의. "--delete-target false" 는 에러
② 삭제 방지 해제         구 인스턴스에만
③ 최종 스냅샷 남기고 삭제  groble-prod-mysql-80-final
```

**결과**

```
남은 인스턴스   groble-prod-mysql  8.4.11  available  삭제방지 True
최종 스냅샷     groble-prod-mysql-80-final  (8.0.45, 20GB, 암호화, available)
알람            6개 전부 OK
terraform plan  No changes
앱              헬스체크 200 (삭제 전 구간 내내 200 유지)
```

### 남은 것

**확장 지원 과금 $0 확인**뿐이다. CE 반영에 1~2일 걸리므로 8/30~8/31 에 확인한다.

```bash
aws ce get-cost-and-usage --profile groble-terraform --region us-east-1 \
  --time-period Start=2026-08-28,End=2026-09-02 --granularity DAILY --metrics UnblendedCost UsageQuantity \
  --filter '{"And":[{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}},
                    {"Dimensions":{"Key":"USAGE_TYPE","Values":["APN2-ExtendedSupport:Yr1-Yr2:MySQL8.0"]}}]}'
```

**전환일(8/29) 이후 `$0.00 / 0 vCPU-hour` 이면 목적 달성이다.**

---

## 6. 부수 항목 (이번 범위 밖)

작업 중 확인된 것들이다. 이번 업그레이드와 직접 관계는 없지만 기록해 둔다.

1. **✅ 해소됨 (2026-08-28)** — ~~백업 창이 한국 점심시간이다.~~ `03:00–04:00 UTC` = **12:00–13:00 KST**.
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
