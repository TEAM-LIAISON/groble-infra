# Phase 5 — Dev MySQL → RDS

> [← Phase 8](./phase-08-prod-asg.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 →](./phase-09-dev-cache-asg.md)

| | |
|---|---|
| **상태** | ✅ **완료** (2026-09-01). 관찰 기간은 롤백 자산이 없어 생략했다 |
| **목적** | Dev 로컬 디스크 MySQL 컨테이너를 RDS 로 옮긴다. dev 엔진 버전을 prod 와 일치시켜 §3-5 promote 게이트의 전제를 만든다 |
| **선행 조건** | **없다.** Phase 3·6·7·8 어디에도 의존하지 않는다 (아래 [순서 근거](#왜-순서를-앞당기는가)) |
| **사용자 영향** | Dev 만. 컷오버 중 **쓰기 차단 1분 미만**(B단계 실측: 덤프 1초 + 복원 15초) + 재배포 시간 |
| **되돌리기** | 컨테이너 제거 전까지 단계별. 제거 후에는 불가 |
| **비용** | **+$20/월** (`db.t4g.micro` ~$18 + 스토리지 ~$2) |

> **이 Phase 는 2026-08-31 이전에 "Phase 8"(Dev 전환) 의 일부였다.** RDS·ElastiCache·ASG 를
> 한 문서에 담고 있었는데, RDS 이관만 선행 조건이 없어 떼어내 **5번으로 앞당기고** 나머지는
> **[9](./phase-09-dev-cache-asg.md)(Dev ElastiCache + ASG)** 로 남겼다.
> 그때 뒤의 Phase 들이 한 칸씩 밀렸다 — 번호 대응표는
> [이관 절차 목차](../infra-ha-migration-runbook.md#번호-이력--옛-문서pr-의-번호는-다를-수-있다)에 있다.

---

## 왜 순서를 앞당기는가

Phase 6·7·8 을 기다릴 이유가 없고, 오히려 **먼저 해야 이득인 것이 세 가지** 있다.

1. **[Phase 2](./phase-02-observability.md) 부터 계속 발화 중인 `컨테이너 메모리 하드리밋 근접` 알람이 멎는다.**
   "어차피 Dev 전환에서 컨테이너째 사라지니 리밋을 상향하지 않는다"고 결정하며 발화를 감수해 둔 건이다.
   그 "어차피"를 앞당기면 감수 기간이 끝난다.
2. **dev 노드에서 256 MiB 가 회수된다.** [9](./phase-09-dev-cache-asg.md) 는 dev 노드를
   t3.medium(4 GiB) → t3.small(2 GiB) 로 낮추는데, MySQL 컨테이너가 남아 있으면 예산이 성립하지 않는다.
   **Phase 5 는 Phase 9 의 선행 조건이다.**
3. **dev 엔진이 prod 와 같아진다.** 지금 dev 는 컨테이너 **MySQL 8.0.46**, prod 는 **RDS 8.4.11** 이다.
   "동일 이미지를 Dev 에 먼저 배포해 통과하면 Prod 로 승격"(계획서 §3-5)이라는 게이트인데
   **DB 엔진부터 갈라져 있으면 게이트가 검증하는 게 없다.**

**의존이 없다는 근거**

| 걸릴 법한 것 | 실제 |
|---|---|
| [Phase 3](./phase-03-nat-gateway.md) (NAT GW) | RDS 는 VPC 내부다. 아웃바운드 경로와 무관 |
| [Phase 6](./phase-06-deployment-controller.md) (rolling 전환) | 지금의 CodeDeploy Blue/Green 으로 컷오버 가능. 아래 절차가 그것을 전제로 쓰여 있다 |
| [Phase 7](./phase-07-elasticache.md) (Prod Redis) | 자원이 겹치지 않는다 |
| [Phase 8](./phase-08-prod-asg.md) (Prod ASG) | prod 노드만 건드린다 |

---

## 사전 실측 (2026-08-31)

**dev 노드 `i-0c8870fff57255a76` · 모니터링 노드 Prometheus 에서 측정했다.** 사이징과 절차의 근거다.

| 항목 | 값 | 이것이 정하는 것 |
|---|---|---|
| `groble_develop_database` 크기 | **21.4 MB** / 110 테이블 | `allocated_storage = 20`(RDS 최소값)으로 충분. 덤프/복원이 수 분에 끝난다 |
| `/opt/mysql-dev-data` 디렉터리 | 315 MB | 대부분 redo·undo·ibdata. 실데이터는 위 21 MB |
| 최대 테이블 | `orders` 11,311행 4.58 MB · `order_items` 9,798행 2.02 MB | — |
| **DEFINER 객체** | **0건** — routine · trigger · view · event 전부 없음 | 🟢 **복원 시 DEFINER 권한 문제가 발생하지 않는다** |
| 컨테이너 엔진 | 8.0.46 | → RDS 8.4.11. 상위 버전 복원이라 정상 |
| `gtid_mode` | **OFF** | `mysqldump --set-gtid-purged=OFF` 불필요 |
| `groble_root` 인증 플러그인 | **`caching_sha2_password`** | 🟢 아래 참조 |
| 앱 연결 방식 | **`TCP/IP`** (평문, TLS 아님) | 🟢 아래 참조 |
| `groble_root` 권한 | `ALL PRIVILEGES ON groble_develop_database.*` 뿐 (SUPER 없음) | 🟢 `read_only=ON` 으로 앱 쓰기를 막을 수 있다 — 컷오버 절차의 근거 |
| DB 기본 콜레이션 | `utf8mb4_0900_ai_ci` | RDS 8.4 기본값과 동일 |
| 테이블 콜레이션 | **`utf8mb4_0900_ai_ci` 52 / `utf8mb4_unicode_ci` 58 로 갈려 있음** | 복원엔 무해(덤프의 CREATE TABLE 이 명시적으로 들고 간다). 다만 별건 → [향후 개선](../infra-future-improvements.md) |
| dev-mysql 컨테이너 메모리 | **253.3 / 256 MiB = 98.9%** (14일 max 255.6) | 알람 발화의 실황 |

### 🟢 인증 플러그인 우려는 실측으로 해소됐다

RDS 8.4 신규 인스턴스의 마스터 유저는 `caching_sha2_password` 다 (prod 의 `groble_root` 가
`mysql_native_password` 인 것은 8.0 에서 넘어온 잔재일 뿐이다). 이 플러그인은 **평문 연결에서
전체 인증을 하려면 JDBC 에 `allowPublicKeyRetrieval=true` 나 TLS 가 필요해서**, 앱 설정을
백엔드에 물어봐야 하는 것 아닌지가 쟁점이었다.

**물어볼 필요가 없다.** 지금 dev 컨테이너의 `groble_root` 가 **이미 `caching_sha2_password`** 이고
(공식 `mysql:8.0` 이미지 기본값), 앱은 그것에 **평문 `TCP/IP` 로 붙어 있다.**
컨테이너가 14일간 5회 재시작하며 인증 캐시가 매번 비워졌는데도 붙었으므로,
**앱 JDBC 설정은 이미 전체 인증 경로를 통과하고 있다.** RDS 로 옮겨도 같은 모양이다.

> 다만 **컷오버 후 첫 연결은 반드시 눈으로 확인한다.** RDS 는 `rds.force_ssl = 0`(기본)이라
> 평문이 허용되지만, 확인 없이 넘어갈 자리는 아니다.
> 참고로 이 상황은 **dev↔RDS 구간이 평문**이라는 뜻이기도 하다. TLS 강제는 별건이다.

---

## 코드 변경 — 모듈을 그대로 재사용할 수 없다

`modules/infrastructure/rds-mysql` 를 dev 에서 다시 부르면 **apply 가 실패한다.** 아래 세 건을 먼저 고친다.

### ① 🔴 `db_subnet_group` 이름이 환경별로 갈리지 않는다 — apply 차단

파라미터 그룹은 `${project}-${environment}-...` 인데 **서브넷 그룹만 `environment` 가 빠져 있다.**

```hcl
# modules/infrastructure/rds-mysql/main.tf:7  (현재)
name = "${var.project_name}-mysql-subnet-group"
```

계정에 `groble-mysql-subnet-group` 하나가 이미 있다(2a/2c). dev 가 같은 모듈을 부르면
`DBSubnetGroupAlreadyExists` 로 죽는다.

**prod 쪽 이름을 바꾸면 안 된다** — 서브넷 그룹은 이름이 force-new 속성이라 replace 가 걸리고,
붙어 있는 prod RDS 수정까지 딸려 온다. **기본값을 현재 이름으로 둔 변수를 새로 추가**해서
prod 는 diff 가 0 이 되게 하고, dev 만 다른 값을 넘긴다.

```hcl
# variables.tf 에 추가
variable "db_subnet_group_name" {
  description = <<-EOT
    DB 서브넷 그룹 이름. null 이면 "${project_name}-mysql-subnet-group" —
    prod 가 이미 쓰고 있는 이름이라 기본값을 바꾸면 replace 가 걸린다.
    dev 는 반드시 명시적으로 다른 이름을 넘긴다.
  EOT
  type        = string
  default     = null
}

# main.tf
name = coalesce(var.db_subnet_group_name, "${var.project_name}-mysql-subnet-group")
```

dev 는 `db_subnet_group_name = "groble-dev-mysql-subnet-group"` 를 넘긴다.

### ② 쓰지 않는 mysql8.0 파라미터 그룹까지 딸려 생성된다

모듈이 `aws_db_parameter_group.mysql_params`(family `mysql8.0`)를 여전히 만든다.
prod 는 8.4 로 올라가며 `mysql_params_84` 로 갈아탔고 8.0 그룹은 state 에만 남아 있는 잔재다.
dev 가 그대로 부르면 **쓰지도 않을 `groble-dev-mysql-params` 가 새로 생긴다.**

```hcl
variable "create_legacy_80_parameter_group" {
  description = "prod 의 8.0 시절 잔재. 신규 환경은 false. 제거는 Phase 12"
  type        = bool
  default     = true   # prod 무영향
}

resource "aws_db_parameter_group" "mysql_params" {
  count = var.create_legacy_80_parameter_group ? 1 : 0
  ...
}
```

dev 는 `false`. **prod 의 8.0 그룹 제거 자체는 [Phase 12](./phase-12-cleanup.md) 로 넘긴다.**

> 🔴 **`count` 를 붙이면 prod state 주소가 바뀐다.** 확인한 현재 주소는 인덱스가 없다:
> ```
> module.rds_mysql.aws_db_parameter_group.mysql_params        ← 현재
> module.rds_mysql.aws_db_parameter_group.mysql_params[0]     ← count 추가 후
> ```
> Terraform 은 이 둘을 **다른 리소스로 보고 destroy + create 를 계획한다.**
> 중단 기준의 "예상하지 못한 삭제/재생성" 에 해당한다.
>
> **모듈은 prod 와 dev 가 공유하므로 이 처리를 미룰 수 없다.** dev 만 apply 하고 넘어가면
> 나중에 누군가 다른 이유로 prod 를 apply 할 때 그 사람이 이 계획을 만나게 된다.
> A단계에서 **AWS 를 건드리지 않는 state 이동**으로 끝낸다 (아래 절차 2번).
>
> 서브넷 그룹은 `count` 가 아니라 `coalesce` 라 **주소도 이름도 그대로다** —
> prod 는 diff 가 생기지 않는다.

### ③ ⚠️ `prevent_destroy = true` 는 변수로 뺄 수 없다

모듈의 `lifecycle` 블록에 하드코딩되어 있는데, **Terraform 은 `lifecycle` 메타인자에 변수를 허용하지 않는다**
(리터럴이어야 한다). 즉 **dev RDS 도 `terraform destroy` 로는 지워지지 않는다.**

고치지 않고 그대로 둔다. dev 와 prod 를 **같은 모듈로 유지하는 것이 이 Phase 의 목적**이고,
모듈을 갈라 놓으면 promote 게이트의 의미가 다시 약해진다. 대신 탈출구를 여기 적어 둔다:

> **dev RDS 를 실제로 지워야 할 때** — 모듈의 `prevent_destroy = true` 를 일시적으로 주석 처리하고
> `terraform destroy -target=module.dev_rds_mysql` 한 뒤 되돌린다. `deletion_protection = false`,
> `skip_final_snapshot` 도 함께 봐야 한다 (아래 tfvars 참조).

---

## 보안그룹 — dev 용 RDS SG 를 새로 만든다

`groble-rds-mysql-sg` 의 인그레스는 prod-target · api-task · monitor 셋뿐이라
**dev 노드가 들어 있지 않다.** 별도 SG 를 만든다 (`modules/infrastructure/security-groups`).

```hcl
resource "aws_security_group" "groble_rds_mysql_dev_sg" {
  name        = "${var.project_name}-rds-mysql-dev-sg"
  description = "Security group for Dev RDS MySQL instance"
  vpc_id      = var.vpc_id

  # dev 노드 — 덤프/복원 작업 + host-mode 컨테이너의 egress 가 이 SG 를 탄다
  ingress { from_port = 3306, to_port = 3306, protocol = "tcp"
            security_groups = [aws_security_group.groble_dev_target_group.id] }

  # API 태스크 (awsvpc)
  ingress { from_port = 3306, to_port = 3306, protocol = "tcp"
            security_groups = [aws_security_group.groble_api_task_sg.id] }

  # 모니터링 노드 — rds-exporter + SSM 포트 포워딩 경유지 (docs/developer-access.md)
  ingress { from_port = 3306, to_port = 3306, protocol = "tcp"
            security_groups = [aws_security_group.groble_monitor_target_group.id] }
}
```

**dev target SG 인그레스가 절차상 핵심이다.** MySQL 컨테이너가 `host` 네트워크 모드라
컨테이너의 egress 가 곧 dev 노드의 SG 다 — 덕분에 **노드에 mysql 클라이언트를 설치하지 않고
컨테이너 안의 클라이언트로 바로 RDS 에 복원할 수 있다** (아래 절차 참조).

> ⚠️ **이 SG 로 prod/dev 가 갈리지는 않는다.** `groble-api-task-sg` 는 dev 와 prod API 태스크가
> **공유**한다. 즉 위 SG 는 prod 태스크에서도 열리고, 반대로 **지금도 dev 태스크는 prod RDS 에
> 네트워크상 닿는다.** 이번 범위 밖으로 두고
> [향후 개선 Medium-6](../infra-future-improvements.md#medium-6) 에 남겼다.

---

## Terraform 설정값 — 백업·점검창을 반드시 명시한다

### ⚠️ 모듈 기본값은 한국 근무시간이다

```hcl
# modules/infrastructure/rds-mysql/variables.tf
backup_window      = "03:00-04:00"        # UTC → KST 12:00~13:00  ← 점심시간
maintenance_window = "sun:04:00-sun:05:00" # UTC → KST 일 13:00~14:00
```

**RDS 의 창은 전부 UTC 다.** prod 는 2026-08-28 에 이 함정을 밟고 값을 옮겼는데
(`environments/prod/variables.tf` 의 주석 참조), **dev 는 명시하지 않으면 기본값을 그대로 받는다.**

### dev 값

```hcl
# environments/dev/terraform.tfvars   (⚠️ .gitignore 대상 — variables.tf 의 default 로도 박아 둔다)

rds_instance_class          = "db.t4g.micro"
rds_allocated_storage       = 20            # 최소값. 실데이터 21.4 MB
rds_max_allocated_storage   = 100

# ⚠️ UTC 다. prod(18:00-19:00 / sun:19:00-sun:20:00)와 겹치지 않게 한 시간 앞에 둔다.
rds_backup_window           = "17:00-18:00"          # KST 02:00~03:00
rds_maintenance_window      = "sun:18:00-sun:19:00"  # KST 월요일 03:00~04:00
rds_backup_retention_period = 7                      # prod 와 동일

rds_multi_az                = false
rds_availability_zone       = "ap-northeast-2c"      # dev 노드와 같은 AZ — cross-AZ 제거
rds_deletion_protection     = true
rds_skip_final_snapshot     = false
```

**창 배치 근거 세 가지**
- **UTC 다.** 위 값은 KST 새벽 2~4시에 해당한다
- **백업창과 점검창을 인접시키되 겹치지 않게 둔다.** RDS 는 두 창이 중첩하면 수정을 거부한다
- **prod 창(KST 03~05시)과 어긋나게 둔다.** 같은 시각에 두 인스턴스가 동시에 백업/점검을 돌 이유가 없다

**백업 보존 7일** — prod 와 맞춘다. 백업 스토리지는 할당량(20 GB) 이내까지 무료이고
실데이터가 21 MB 라 사실상 비용이 0 이다. 짧게 잡아 아낄 것이 없고, 값이 갈리면
"dev 는 prod 와 같은 형태"라는 이 Phase 의 명분이 흐려진다.

**AZ 를 코드에 고정한다.** prod RDS 는 `availability_zone` 이 비어 있어 재생성 시 AZ 가 바뀔 수 있는
상태다(계획서 §2.2). dev 는 처음부터 2c 로 박아 dev 노드(2c)와 정렬시킨다.

### 그 밖의 코드 변경

| 파일 | 변경 |
|---|---|
| `environments/dev/main.tf` | `data "aws_subnets" "shared_private_subnets"` **추가** — 지금은 2c 단일 서브넷(`dev_api_subnet`)밖에 없어 서브넷 그룹을 만들 수 없다 (RDS 는 2개 AZ 이상 요구) |
| `environments/dev/main.tf` | `module "dev_rds_mysql"` 추가 |
| `environments/dev/main.tf` | `module.dev_api_service.db_host` : `data.aws_instance.shared_dev_instance.private_ip` → `module.dev_rds_mysql.rds_address` |
| `environments/dev/main.tf` | `module "rds_alarms"` 추가 — `db_instance_identifier = module.dev_rds_mysql.rds_instance_identifier`, 통지는 `alerts_sns_topic_arn_dev` |
| `environments/shared/` | dev RDS SG 리소스 + `rds_mysql_dev_security_group_id` output |

> ⚠️ **`rds_instance_id` 가 아니라 `rds_instance_identifier` 다.** `aws_db_instance.id` 는
> `DbiResourceId` 를 반환하므로 알람이 존재하지 않는 지표를 **에러 없이 조용히** 감시하게 된다
> (`modules/observability/rds-alarms/outputs.tf` 의 경고 참조).

---

## A단계 완료 기록 (2026-08-31)

**배포된 것**

| | 값 |
|---|---|
| prod state 이동 | `mysql_params` → `mysql_params[0]`. 이동 후 `terraform plan` **No changes** 확인 |
| shared apply | `1 to add, 0 to change, 0 to destroy` — `groble-rds-mysql-dev-sg` = **`sg-07cc30a39fbb7be30`** |
| dev apply | `9 to add, 0 to change, 0 to destroy` — **기존 리소스 변경 0건** |
| RDS 엔드포인트 | `groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com:3306` |
| 생성 소요 | 9분 42초 |

**실물 확인 (`describe-db-instances`)** — 전부 의도한 값이다.

| 항목 | 값 |
|---|---|
| 엔진 / 상태 | **8.4.11** / `available` |
| 클래스 / AZ | `db.t4g.micro` / **ap-northeast-2c** |
| 백업창 / 점검창 | **`17:00-18:00`** / **`sun:18:00-sun:19:00`** (UTC → KST 02~03시, 월 03~04시) |
| 보존 / 스토리지 | 7일 / 20 → 100 GB, 암호화 O |
| 서브넷 그룹 | `groble-dev-mysql-subnet-group` (2a + 2c) |
| 파라미터 그룹 | `groble-dev-mysql-84-params` (**8.0 그룹은 생성되지 않았다**) |
| SG / 공개 / 삭제보호 | `sg-07cc30a39fbb7be30` / false / true |

**dev 노드 컨테이너에서 접속 확인** — 파라미터가 실제로 먹었고 prod 와 일치한다.

| 항목 | 값 | |
|---|---|---|
| `VERSION()` | 8.4.11 | 접속 성공 |
| `innodb_buffer_pool_size` | **256 MiB** | prod 와 동일 |
| `innodb_dedicated_server` | 0 | 명시값이 먹는 조건 |
| `max_connections` / `binlog_format` / `log_output` | 200 / ROW / TABLE | prod 와 동일 |
| `innodb_redo_log_capacity` | 2048 MiB | prod 와 동일 |
| DB 문자셋 | `utf8mb4` / `utf8mb4_0900_ai_ci` | 컨테이너 DB 기본값과 일치 |
| `groble_root` 플러그인 | `caching_sha2_password` | 예상대로 |
| `@@read_only` | 0 | |

### 🟢 예상과 달랐던 것 — RDS 연결은 TLS 다

컨테이너 MySQL 로의 연결은 평문(`TCP/IP`)이었는데, **RDS 로의 연결은 `TLS_AES_256_GCM_SHA384` 로 붙었다.**
RDS 가 인증서를 제시하고 MySQL 8 클라이언트 기본값이 `--ssl-mode=PREFERRED` 라 자동으로 협상된다.

- **이관의 부수 효과로 dev DB 구간이 암호화된다.** 의도한 것은 아니지만 개선이다
- `caching_sha2_password` 우려가 한 겹 더 사라진다 — TLS 위에서는 공개키 교환이 필요 없다
- ⚠️ **다만 앱(Connector/J)이 같은 선택을 하는지는 아직 확인하지 않았다.**
  Connector/J 8.x 도 `sslMode=PREFERRED` 가 기본이라 TLS 로 붙을 가능성이 높지만,
  **검증은 컷오버(C단계 12번) 때 한다.** 위 결과는 mysql CLI 의 동작일 뿐이다

**확인하지 못한 것**: 앱의 실제 연결. 자동 백업 1회 생성(첫 백업창은 KST 익일 02시).

---

## B단계 완료 기록 (2026-08-31) — 리허설

**덤프·복원이 실제로 통과했다.** 아래 수치는 C단계 컷오버의 소요 예측 근거다.

| | 값 |
|---|---|
| 덤프 소요 / 크기 | **1초** / 13 MB (4,349줄) |
| `CREATE TABLE` | **110** |
| **`DEFINER=` 포함** | **0건** — 사전 실측대로 권한 문제가 없다 |
| 복원 소요 | **15초** (무오류, 종료코드 0) |
| **쓰기 동결 예상 구간** | **1분 미만** — 덤프+복원 16초 + 대조 |

**대조 결과 — 전부 일치**

| 항목 | 컨테이너 | RDS |
|---|---|---|
| BASE TABLE 수 | 110 | 110 |
| **행 수 일치** | **110 / 110** (불일치 0) | |
| 전체 행 수 | 51,492 | 51,492 |
| 인덱스 수 | **567** | **567** |
| 콜레이션 `utf8mb4_0900_ai_ci` | 52 | 52 |
| 콜레이션 `utf8mb4_unicode_ci` | 58 | 58 |

> 참고: `data_length + index_length` 는 컨테이너 21.4 MB / RDS 27.3 MB 로 다르게 나온다.
> 이 값은 InnoDB 의 **페이지 추정치**이고 갓 임포트한 쪽은 통계가 최신이라 그렇다.
> **권위 있는 대조는 행 수와 인덱스 수이고 둘 다 정확히 일치한다.**

### 덤으로 검증한 것 — `DROP DATABASE` 는 Terraform 드리프트를 만들지 않는다

C단계 8번이 리허설 데이터를 지우려고 `DROP DATABASE` / `CREATE DATABASE` 를 하는데,
`aws_db_instance` 의 `db_name` 이 이것을 드리프트로 잡으면 컷오버 도중에 예상치 못한
plan 이 나온다. **미리 확인했다:**

```
DROP DATABASE groble_develop_database;
CREATE DATABASE groble_develop_database CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
→ terraform plan: No changes.
```

RDS API 의 `DBName` 은 **생성 시점의 메타데이터**라 스키마를 지워도 따라가지 않는다.

**현재 RDS 상태**: 리허설 데이터를 지우고 **빈 `groble_develop_database`(utf8mb4 / utf8mb4_0900_ai_ci)** 만
남겨 뒀다. C단계는 8번의 `DROP/CREATE` 를 건너뛰고 바로 복원해도 되지만,
**절차대로 다시 돌리는 편을 권한다** — 그 사이에 누가 무엇을 넣었는지 보증할 수 없다.

---

## 역할 분담 — 인프라는 RDS 와 `DB_HOST`, 백엔드는 데이터와 배포

| 단계 | 담당 | 상태 |
|---|---|---|
| **A. RDS·SG·알람 생성** | 인프라 | ✅ 완료 (2026-08-31) |
| **B. 덤프/복원 리허설** | 인프라 | ✅ 완료 (2026-08-31) |
| **C. 컷오버** | **백엔드 + 인프라 (합동)** | ⏳ 진행 요청 — [요청서](../handoff/closed/dev-rds-cutover.md) |
| ├ C1 쓰기 동결 · 덤프 · 복원 · 대조 | 백엔드 | ✅ 완료 (2026-09-01) |
| ├ C2 `DB_HOST` 전환 apply | **인프라** | ✅ 완료 — rev **1191** (2026-09-01) |
| └ C3 배포 · 검증 | 백엔드 | ✅ 완료 — rev **1192** |
| **D. 관찰** | — | ⏭️ **생략** (롤백 자산이 없어 관찰의 판단 근거가 사라졌다) |
| **E. 자원 정리** (컨테이너 서비스 제거) | 인프라 | ✅ 완료 (2026-09-01) |

### `DB_HOST` 는 이 리포가 정하고, 배포는 백엔드가 한다

**태스크 정의를 등록하는 주체가 둘이다.**

```
groble-dev-task:1181  registeredBy = .../groble-terraform          ← 이 리포
groble-dev-task:1190  registeredBy = user/groble-github-actions    ← 앱 CD 워크플로
```

`aws_ecs_service.api_service` 에 `lifecycle { ignore_changes = [task_definition] }` 가 걸려 있어
**Terraform apply 만으로는 배포되지 않는다.** 리비전이 하나 생길 뿐이다.

**그러나 그 리비전은 버려지지 않는다.** CD 워크플로가
`describe-task-definition --task-definition <family>`(리비전 미지정 = **최신 ACTIVE**)를 읽어
**이미지만 갈아끼우므로, Terraform 이 등록한 리비전이 다음 배포의 기반이 된다.**
즉 `apply` → (앱 배포) 순서면 환경변수가 자동으로 실려 간다.

**[Phase 4](./phase-04-monitoring-node-rebuild.md) 에서 실제로 그렇게 동작했다:**

| rev | 등록자 | `OTEL_EXPORTER_OTLP_ENDPOINT` |
|---|---|---|
| 1180 | github-actions | `http://10.0.1.193:4318` |
| **1181** | **terraform** | **`http://otel.internal.groble.im:4318`** ← 이 리포가 바꿨다 |
| 1182 | github-actions (11분 뒤) | `http://otel.internal.groble.im:4318` ← **승계됐다** |

CD 가 자체 태스크 정의 JSON 을 들고 있었다면 1182 에서 옛 값으로 되돌아갔을 것이다.

> 그래서 **백엔드가 `DB_HOST` 를 직접 고칠 필요가 없다.** 앱 yml 도 손대지 않는다 —
> 태스크 정의의 환경변수가 yml 을 이긴다.

### 🔴 apply 전에 `spring_app_image` 를 실행 중 이미지와 맞춘다

같은 메커니즘이 함정이기도 하다. `environments/dev/terraform.tfvars` 의 `spring_app_image` 가
낡은 채로 apply 하면 **그 낡은 이미지가 family 의 최신 리비전이 되고**, 이미지를 갈아끼우지 않는
배포(롤백·재배포)가 그것을 띄운다. [Phase 4](./phase-04-monitoring-node-rebuild.md) 가 경고해 둔 것과 같은 함정이다.

```bash
# 실행 중 이미지 확인 → tfvars 에 반영
aws ecs describe-services --cluster groble-cluster --services groble-dev-service \
  --profile groble-terraform --query 'services[0].taskDefinition' --output text \
| xargs -I{} aws ecs describe-task-definition --task-definition {} --profile groble-terraform \
  --query 'taskDefinition.containerDefinitions[0].image' --output text
```

> ⚠️ **tfvars 는 `.gitignore` 대상이라 이 값이 git 에 남지 않는다.** 바꿀 때 주석으로 이전 값을 남긴다.

### 🔴 그래서 apply 는 복원 **뒤**에 한다

apply 하는 순간부터 **"다음 배포"가 RDS 를 본다.** 데이터 이관 전에 apply 해 두면
그 사이 아무 PR 이나 머지되어 CD 가 돌 때 **dev 앱이 빈 RDS 를 보게 된다**
(dev 는 2일에 한 번꼴로 배포된다 — 14일에 리비전 7개).

**복원·대조가 끝난 뒤에 apply 한다.** 그 대신 컷오버가 백엔드 단독 작업이 아니라
**짧은 합동 작업**이 된다 — apply 자체는 1분이면 끝난다.

---

## C단계 기록 (2026-09-01) — ⚠️ 계획과 다르게 흘렀다

### 배포된 것 (C2)

| | 값 |
|---|---|
| `spring_app_image` 동기화 | `dev-b0f9819-20260830-080851` → **`dev-03ed5a4-20260831-182641`** (실행 중 rev 1190 과 일치) |
| `db_host` | `data.aws_instance.shared_dev_instance.private_ip` → **`module.dev_rds_mysql.rds_address`** |
| plan | `1 to add, 0 to change, 1 to destroy` — destroy 는 아무도 실행하지 않는 rev 1181 의 deregister |
| 결과 | **rev 1191** 등록. family 의 최신 ACTIVE 이므로 다음 배포에 실려 간다 |
| 확인 | `DB_HOST` = RDS · `DB_USERNAME`/`DB_NAME` 불변 · `REDIS_HOST` 불변(10.0.12.215, Phase 9 까지) · 이미지 일치 |
| state 되돌리기 지점 | `tqSdp5LSDH5J..ptQ3HnC83U08xN6tqS` |

### 🔴 계획과 달랐던 것 — 구 컨테이너 DB 가 먼저 비워졌다

C2 직전 확인에서 **컨테이너의 `groble_develop_database` 가 테이블 0개**로 나왔다.
DB 자체는 존재하고 데이터 디렉터리(224 MB)도 남아 있으나 스키마 하위 파일이 0 이다.
`read_only` 도 0(해제)이었다.

**컨테이너 DB 를 비우는 것은 원래 E단계(2~3일 관찰 후) 작업이었다.** 결과:

- **롤백 경로가 사라졌다.** 아래 [롤백](#롤백) 표의 "컨테이너가 살아 있다" 전제가 깨졌다
- **행 수 대조 게이트를 수행할 수 없었다** — 비교 대상이 없다.
  RDS 내부 정합성(**테이블 110 · 인덱스 567**, B단계 기준선과 정확히 일치)만 확인했다
- **C2·C3 가 예정된 절차가 아니라 복구가 됐다** — 앱이 빈 DB 를 보고 있어 dev 가 멈춘 상태다

**데이터 자체는 안전하다.** RDS 행 수가 B단계 기준선보다 늘어 최종 덤프가 제대로 잡혔음을 보여준다.

| 테이블 | B단계 기준선 (2026-08-31) | C1 복원 후 |
|---|---|---|
| `orders` | 11,311 | **11,719** |
| `order_items` | 9,798 | **11,720** |
| `purchases` | 1,159 | **1,172** |
| `contents` | 869 | **884** |

**남은 복구 수단은 RDS 자체의 것뿐이다** — 자동 스냅샷 2개(08-31 11:34 · 17:04 UTC)와
PITR(09-01 05:35 UTC 까지). 노드의 `/tmp/dev-rehearsal.sql`(B단계 리허설 덤프)은
RDS 보다 낡아 쓸모가 없다.

> **교훈**: 요청서 §4-2 의 "대상 비우기" 명령은 `-h $RDS` 하나로 대상과 원본이 갈린다.
> 같은 셸에서 원본과 대상을 오가는 절차는 이런 사고에 열려 있다.
> [Phase 9](./phase-09-dev-cache-asg.md) 이후 비슷한 이관이 있으면
> **원본 쪽 명령과 대상 쪽 명령의 프롬프트를 물리적으로 분리**하는 편이 낫다.

---

## ✅ 완료 요약 (2026-09-01)

**배포된 것**

| | |
|---|---|
| Dev DB | 컨테이너 MySQL 8.0.46 → **RDS `groble-dev-mysql` (MySQL 8.4.11, db.t4g.micro, private 2c)** |
| 전용 SG | `groble-rds-mysql-dev-sg` (`sg-07cc30a39fbb7be30`) |
| 알람 | RDS 6종 → `#groble-alert-dev` |
| 앱 | rev **1192** (CD 가 인프라의 rev 1191 에서 `DB_HOST` 승계) |
| 제거 | ECS 서비스 `groble-dev-mysql-service` · 태스크 정의 `groble-dev-mysql-task:40` |
| 남긴 것 | 노드의 `/opt/mysql-dev-data` (211 MB) — [9](./phase-09-dev-cache-asg.md) 노드 교체에서 소멸 |
| 비용 | **+$20/월** |

**검증 결과**

- dev API 태스크 rev 1192 healthy · ALB 타깃 healthy
- RDS 에 앱 커넥션 6개(`10.0.12.160`), `Com_select` 증가 확인 → 실트래픽 처리 중
- 컨테이너 MySQL `Exited (0)` 정상 종료, cAdvisor 노출 중단, Prometheus 시계열 소멸
- **dev 노드 MemAvailable 2,080 → 2,357 MiB (+277 MiB 회수)** — [9](./phase-09-dev-cache-asg.md) 의 t3.small 예산 전제
- `컨테이너가 메모리 하드리밋에 근접` 알람: 규칙의 `noDataState = OK` 이고 시계열이 사라져 자동 해소된다

**계획과 달랐던 점**

1. **구 컨테이너 DB 가 C1 시점에 비워졌다** (원래 E단계 작업). 롤백 경로가 사라졌고
   행 수 대조 게이트를 수행할 수 없었다 — 자세한 내용은 아래 [C단계 기록](#c단계-기록-2026-09-01--계획과-다르게-흘렀다)
2. **D단계(2~3일 관찰)를 생략했다.** 관찰의 목적은 "되돌릴지 판단"이었는데
   되돌릴 대상이 없어 근거가 소멸했다. 대신 컨테이너 제거 직전에 앱이 RDS 를
   실제로 쓰고 있는지를 커넥션·쿼리 수준에서 확인했다
3. **`DB_HOST` 전환 방식이 문서 초안과 반대였다.** "Terraform 리비전은 배포되지 않으므로
   백엔드가 직접 고쳐야 한다"고 적었으나, CD 가 최신 ACTIVE 리비전을 기반으로
   이미지만 갈아끼우므로 **인프라가 apply 하면 다음 배포에 실려 간다.**
   rev 1191(terraform) → 1192(CD 승계)로 실증됐다

**검증하지 못한 것**

- **RDS 데이터의 원본 대조.** 비교 대상(컨테이너 DB)이 이관 전에 사라졌다.
  테이블 110 · 인덱스 567 이 B단계 기준선과 일치하는 것까지만 확인했다
- 자동 백업은 생성돼 있으나(08-31 11:34 · 17:04 UTC) **복원 테스트는 하지 않았다**

**롤백**

**불가능하다.** 컨테이너 시절 데이터로 되돌아갈 방법이 없다.
RDS 내부 사고는 스냅샷·PITR(보존 7일)로 복구한다.

---

## 절차

### A. 준비 — 무영향, 앱은 그대로 컨테이너를 본다

1. **모듈·SG 코드 변경** (①②③ + dev RDS SG). 아직 apply 하지 않는다
   ```bash
   terraform -chdir=environments/dev    validate
   terraform -chdir=environments/shared validate
   terraform -chdir=environments/prod   validate
   ```
2. 🔴 **prod state 이동 먼저** — `count` 로 바뀐 주소를 맞춘다. **AWS 를 호출하지 않는다**
   ```bash
   cd environments/prod
   terraform state list | grep mysql_params          # 인덱스 없는 주소 확인
   terraform state mv 'module.rds_mysql.aws_db_parameter_group.mysql_params' \
                      'module.rds_mysql.aws_db_parameter_group.mysql_params[0]'
   terraform plan                                    # ✅ **No changes** 여야 한다
   ```
   > `plan` 에 파라미터 그룹 destroy/create 가 남아 있으면 이동이 안 된 것이다. 여기서 멈춘다.
   > state 는 S3 versioning 으로 이력이 남으므로 되돌릴 수 있다.
3. **`environments/shared` apply** — dev RDS SG 추가
   - ⚠️ plan 에 **기존 SG 의 변경이 하나도 없어야 한다.** 순수 추가다
4. **`environments/dev` apply** — `module "dev_rds_mysql"` + `module "rds_alarms"`
   - ⚠️ **plan 을 육안 확인한다.** 기존 ECS 서비스·태스크 정의에 변경이 잡히면 안 된다.
     **삭제/재생성이 하나라도 보이면 중단한다**
   - `db_host` 는 아직 컨테이너를 가리킨다 — 이 단계에서 앱은 아무것도 바뀌지 않는다
5. RDS 기동 확인 (~10분)
   ```bash
   aws rds describe-db-instances --db-instance-identifier groble-dev-mysql \
     --profile groble-terraform --query \
     'DBInstances[0].{Ver:EngineVersion,AZ:AvailabilityZone,Class:DBInstanceClass,
                      Backup:PreferredBackupWindow,Maint:PreferredMaintenanceWindow,
                      Retention:BackupRetentionPeriod,SG:VpcSecurityGroups[].VpcSecurityGroupId}'
   ```
   - 엔진 **8.4.11** · AZ **ap-northeast-2c** · 클래스 **db.t4g.micro**
   - 백업창 **17:00-18:00** · 점검창 **sun:18:00-sun:19:00** (⚠️ UTC 표기 그대로 나온다)
6. dev 노드에서 접속 확인:
   ```bash
   docker exec $(docker ps -q --filter name=groble-dev-mysql) \
     sh -c 'mysql -h <rds-endpoint> -u groble_root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION();"'
   ```

### B. 리허설 — 데이터는 버린다

7. **앱을 켜 둔 채로** 덤프→복원을 한 번 돌려 본다. 스키마·문자셋·소요시간을 확인하는 게 목적이다.
   여기서 나온 데이터는 C 에서 덮어쓴다.
   ```bash
   C=$(docker ps -q --filter name=groble-dev-mysql)
   docker exec "$C" sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
     --single-transaction --no-tablespaces --routines --triggers --events \
     --hex-blob --default-character-set=utf8mb4 groble_develop_database' > /tmp/dev-rehearsal.sql
   docker exec -i "$C" sh -c 'mysql -h <rds-endpoint> -u groble_root -p"$MYSQL_ROOT_PASSWORD" \
     groble_develop_database' < /tmp/dev-rehearsal.sql
   ```
   - `--set-gtid-purged=OFF` 는 **불필요하다** (실측: `gtid_mode = OFF`)
   - `--routines --triggers --events` 는 실측상 0건이지만, 나중에 생겼을 때 조용히 빠지는 것보다 낫다
   - **`mysql` 스키마는 절대 덤프하지 않는다.** RDS 마스터 유저를 덮어써 접속이 끊긴다
   - 클라이언트는 **컨테이너 안의 것을 쓴다** — 노드에 아무것도 설치하지 않는다
8. 검증 쿼리(아래 [검증](#검증))가 통과하는지 확인

### C. 컷오버 — **합동** 🔴 쓰기 유실 구간이다

> **절차 전문과 접속 정보는 요청서에 있다 → [`handoff/dev-rds-cutover.md`](../handoff/closed/dev-rds-cutover.md)**
> 아래는 인프라 쪽 요약이다.

> **원래 문서에는 이 구간이 없었다.** "덤프→복원" 다음에 바로 "DB_HOST 변경→재배포"가 오는데,
> 그 사이에 앱은 **여전히 컨테이너에 쓰고 있다.** 게다가 Blue/Green 이라 전환 순간
> **blue(컨테이너)와 green(RDS)이 서로 다른 DB 를 보며 동시에 살아 있다** —
> [Phase 7](./phase-07-elasticache.md) 이 Redis 에서 stop-first 를 쓰는 것과 같은 split-brain 이다.
> **DB 레벨에서 쓰기를 얼려** 그 창을 없앤다.

**C1 — 백엔드**

9. **쓰기 동결** — 컨테이너 MySQL 에 `SET GLOBAL read_only = ON`
   - `groble_root` 에 SUPER 가 없으므로(실측) 앱의 쓰기가 실제로 막힌다. 읽기는 계속된다
   - ⚠️ 컨테이너가 재시작하면 `OFF` 로 돌아간다. 14일에 5회 재시작한 이력이 있다
10. **최종 덤프 → 복원** (B단계와 동일. 실측 소요 **16초**)
11. **행 수 대조** — [검증](#검증)의 스크립트. **어긋나면 진행하지 않는다**

**C2 — 인프라** (여기서부터 "다음 배포"가 RDS 를 본다)

12. `terraform.tfvars` 의 `spring_app_image` 를 **실행 중 이미지와 동기화** (위 함정 참조)
13. `environments/dev/main.tf` 의 `db_host` 를
    `data.aws_instance.shared_dev_instance.private_ip` → `module.dev_rds_mysql.rds_address` 로 변경
14. `terraform plan` 육안 확인 → apply. **태스크 정의 리비전 1개 추가 외에 변경이 없어야 한다**

**C3 — 백엔드**

15. **평소대로 배포.** CD 가 방금 등록된 리비전을 기반으로 읽어 `DB_HOST` 를 승계한다
16. green 태스크 healthy · RDS 에 실제로 붙었는지 확인 후 트래픽 전환
17. 컨테이너의 `read_only` 는 **켜 둔 채로 남긴다** — 롤백 자산이 더 갈라지지 않게

### 🟢 바뀌는 값이 `DB_HOST` 하나뿐인 이유

RDS 마스터 계정을 **앱이 지금 쓰는 것과 같은 자격증명으로 만들었다.** 확인했다:

| 환경변수 | 컨테이너 | RDS | 바꾸나 |
|---|---|---|---|
| `DB_HOST` | `10.0.12.215` | `groble-dev-mysql.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com` | **✅ 이것만** (인프라가 C2 에서) |
| `DB_PORT` | 3306 | 3306 | ❌ |
| `DB_NAME` | `groble_develop_database` | 동일 | ❌ |
| `DB_USERNAME` | `groble_root` | 동일 | ❌ |
| `DB_PASSWORD` | (tfvars 값) | **동일** — sha256 대조로 확인 | ❌ |

### D. 관찰 — 컨테이너를 아직 지우지 않는다

18. **2~3일 관찰.** 컨테이너 MySQL 서비스는 `read_only=ON` 상태로 그대로 둔다 (롤백 자산)
19. dev 스모크 테스트 · 알람 정상 · RDS 자동 백업 1회 이상 생성 확인
20. **인프라에 이관 완료를 알린다** → E단계 착수 조건

### E. 정리 — **인프라 소관** 🔴 되돌릴 수 없는 지점

21. `module "dev_mysql_service"` 제거 → apply
22. dev 노드의 `/opt/mysql-dev-data` 는 **바로 지우지 않는다.** 1주 더 둔 뒤
    [9](./phase-09-dev-cache-asg.md) 의 노드 교체에서 자연 소멸시킨다
23. `컨테이너 메모리 하드리밋 근접` 알람이 멎었는지 확인
24. dev 노드 여유 메모리가 ~256 MiB 늘었는지 — [9](./phase-09-dev-cache-asg.md) 예산의 전제

---

## 검증

### 데이터 대조 (C1 11번 단계 — 통과 못 하면 진행 금지)

`information_schema.table_rows` 는 InnoDB **추정치**라 대조에 쓸 수 없다. 실제 `COUNT(*)` 를 돌린다.

**아래 스크립트는 2026-08-31 에 dev 노드에서 실제로 돌려 검증했다** (컨테이너 쪽 절반).
클라이언트는 컨테이너 안의 것을 쓰므로 노드에 아무것도 설치하지 않는다.

```bash
C=$(docker ps -q --filter name=groble-dev-mysql)
DB=groble_develop_database
RDS=<rds-endpoint>

# 1) 테이블 목록 (BASE TABLE 만)
docker exec "$C" sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
  -e \"SELECT table_name FROM information_schema.tables \
       WHERE table_schema='$DB' AND table_type='BASE TABLE' ORDER BY table_name\"" \
  2>/dev/null > /tmp/tables.txt
wc -l < /tmp/tables.txt          # 110 이어야 한다

# 2) 양쪽 행 수를 테이블별로 대조
while read -r t; do
  b=$(docker exec "$C" sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
        -e 'SELECT COUNT(*) FROM \`$DB\`.\`$t\`'" 2>/dev/null)
  a=$(docker exec "$C" sh -c "mysql -h $RDS -u groble_root -p\"\$MYSQL_ROOT_PASSWORD\" -N -B \
        -e 'SELECT COUNT(*) FROM \`$DB\`.\`$t\`'" 2>/dev/null)
  [ "$b" = "$a" ] && echo "ok   $t $b" || echo "MISMATCH $t: 컨테이너=$b RDS=$a"
done < /tmp/tables.txt | tee /tmp/rowdiff.txt

grep -c '^ok' /tmp/rowdiff.txt   # 110 이어야 한다
grep MISMATCH /tmp/rowdiff.txt   # 아무것도 안 나와야 한다
```

> `2>/dev/null` 은 `mysql: [Warning] Using a password on the command line` 를 지우는 용도다.
> 110회 × 2 이라 없으면 출력이 경고로 덮인다.

**기준선 (2026-08-31, 컨테이너 측정값)** — 컷오버 시점에는 늘어나 있겠지만 자릿수 감각용이다.

| | 값 |
|---|---|
| BASE TABLE 수 | **110** |
| 전체 행 수 합 | **51,492** |
| 최대 테이블 | `orders` 11,311 · `order_items` 9,798 |

- [ ] **테이블 110개 전부 행 수 일치**
- [ ] 콜레이션 분포 일치 (`utf8mb4_0900_ai_ci` 52 / `utf8mb4_unicode_ci` 58)
- [ ] 인덱스 수 일치 — `SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema='groble_develop_database'`

### 컷오버 후

- [ ] Dev 애플리케이션 정상 동작 (기능 스모크 테스트)
- [ ] **앱이 RDS 에 실제로 붙었는지** — RDS 쪽 `SHOW PROCESSLIST` 에 dev 태스크 IP 가 보이는지.
      **컨테이너 쪽에 앱 커넥션이 남아 있지 않은지도 함께 본다**
- [ ] **첫 연결이 인증에 성공했는지** (`caching_sha2_password` + 평문 — 위 실측 참조)
- [ ] Dev RDS **자동 백업이 실제로 생성**되었는지 (`describe-db-snapshots --snapshot-type automated`)
- [ ] 백업창·점검창이 **의도한 KST 시각**인지 콘솔에서 재확인 (UTC 함정)
- [ ] Dev RDS 알람 4~6종이 `#groble-alert-dev` 로 도달하는지 (하나를 강제 발화시켜 확인)
- [ ] 구 컨테이너 제거 후 **`컨테이너 메모리 하드리밋 근접` 알람이 멎는지**
- [ ] dev 노드 여유 메모리가 ~256 MiB 늘었는지 — [9](./phase-09-dev-cache-asg.md) 예산의 전제

---

## 롤백

### 🔴 2026-09-01 현재 — 컨테이너로의 롤백은 불가능하다

**C1 시점에 구 컨테이너 DB 가 비워져** 아래 표의 A~D 행이 모두 무효가 됐다.
남은 복구 수단은 **RDS 자체의 스냅샷·PITR 뿐**이다.

| 수단 | 범위 |
|---|---|
| 자동 스냅샷 | 2026-08-31 11:34 · 17:04 UTC |
| PITR | 2026-09-01 05:35 UTC 까지 (보존 7일) |

RDS 안에서 사고가 나면 위로 복구한다. **컨테이너 시절 데이터로 되돌아갈 방법은 없다.**

<details>
<summary>원래 계획했던 롤백 (전제가 깨져 무효)</summary>

| 시점 | 방법 | 잃는 것 |
|---|---|---|
| A·B 단계 | RDS 를 그냥 둔다. 앱은 아직 컨테이너를 본다 | 없음 |
| C 단계 (컷오버 중) | 컨테이너 `read_only=OFF` → `DB_HOST` 를 노드 IP 로 되돌려 apply → 배포 | 컷오버 후 RDS 에 쓰인 데이터 |
| D 단계 (관찰 중) | 위와 동일. 컨테이너 데이터가 동결 시점 그대로 살아 있다 | 컷오버 후 RDS 에 쓰인 데이터 |
| **E 단계 이후** | **불가** | — |

전제는 "구 Dev MySQL 컨테이너가 E단계까지 데이터를 들고 살아 있다"였다.

</details>

---

## 이관 전까지의 상태 — Dev MySQL 컨테이너는 이미 리밋에 붙어 있다

> [Phase 2](./phase-02-observability.md) 에서 `컨테이너 메모리 하드리밋 근접` 알람이 dev-mysql 로
> 계속 발화해 조사했다. **리밋 상향(256 → 384 MiB)을 검토했으나, 어차피 이 Phase 에서
> 컨테이너 자체가 사라지므로 상향하지 않기로 했다.** 여기까지는 알람 발화를 감수한다.

**측정 (2026-08-20, 운영 Prometheus, 직전 14일)**

| 항목 | 값 |
|---|---|
| 컨테이너 하드리밋 | 256 MiB |
| RSS / page cache | **221.8** / 22.7 MiB → 회수 가능한 여유가 **34 MiB 뿐** |
| working set 비율 | **99.1%** (알람 임계 90%) |
| **컨테이너 인스턴스 수 (14일)** | **5개** — 즉 5번 재시작했다 |
| 같은 기간 dev-redis | **1개** (2025-11-11 시작 이후 그대로) |
| dev 노드 부팅 후 경과 | 281일 (노드 사건 아님) |
| 태스크 정의 | 14일 내내 **rev 40 고정** (재배포 아님) |
| 종료된 컨테이너들의 **마지막 usage** | 253.1 · 255.4 · 255.8 · 255.8 · **256.0** MiB |

**2026-08-31 재측정에서도 동일하다** — working set 14일 max **255.6 MiB**, 현재 253.3/256 = **98.9%**,
태스크 정의는 여전히 **rev 40**. 11일이 지나도록 아무것도 나아지지 않았다.

재시작은 dev-mysql 고유이고, 종료 직전 전부 하드리밋에 붙어 있었다.
**다만 사인은 특정하지 못했다** — OOM kill 인지, 메모리 압박으로 `mysqladmin ping`(timeout 10s × retries 3)
헬스체크가 연속 실패해 ECS 가 교체한 것인지 구분할 수 없다.

> 판별이 막힌 이유 세 가지. 같은 조사를 반복하지 않도록 적어 둔다.
> - `container_memory_failcnt` 는 **cgroup v1 지표**라 v2 노드에서 전부 0 으로 나온다
> - ECS 는 중지된 태스크의 `stoppedReason` 을 **1시간만 보관**한다
> - **MySQL 컨테이너 로그는 Loki 로 가지 않는다** (Loki 에는 Spring 앱만 있다)
>
> 다음 재시작을 잡으려면 발생 직후 1시간 안에 `aws ecs describe-tasks --desired-status STOPPED` 를 봐야 한다.

**RDS 사이징 결론**: 컨테이너 RSS 222 MiB · 버퍼풀 128 MiB · **실데이터 21.4 MB**.
`db.t4g.micro`(1 GiB)로 충분하다. 모듈의 8.4 파라미터 그룹이 `innodb_dedicated_server = 0` 과
`innodb_buffer_pool_size = {DBInstanceClassMemory*3/4}` 를 명시한다.
**실측 결과 버퍼풀은 256 MiB 다** — 컨테이너 시절(128 MiB)의 2배이고, **prod 와 정확히 같다.**

> ⚠️ `{DBInstanceClassMemory*3/4}` 를 "인스턴스 메모리 1 GiB × 3/4 = 750 MiB" 로 읽으면 안 된다.
> `DBInstanceClassMemory` 는 물리 메모리가 아니라 **RDS 가 OS·관리 프로세스 몫을 뺀 값**이다.
> db.t4g.micro 에서 이 수식은 256 MiB 로 떨어진다 (db.t3.micro 인 prod 와 같은 값).
> 데이터가 21 MB 라 전량이 버퍼풀에 올라간다.

---

## 이 Phase 에서 자연 해소되는 함정 2가지

**① `MYSQL_INNODB_BUFFER_POOL_SIZE` 는 무효다**

`modules/services/development/mysql-service/main.tf` 의 태스크 정의에
`MYSQL_INNODB_BUFFER_POOL_SIZE = "128M"` 이 환경변수로 들어 있는데,
**공식 `mysql:8.0` 이미지는 이 변수를 읽지 않는다.** 버퍼풀은 MySQL 8 기본값 128 MiB 이고,
우연히 값이 같아 지금까지 문제가 드러나지 않았다.
→ **이 변수를 고쳐서 메모리를 조절하려는 시도는 아무 효과가 없다.** 실제로 바꾸려면
`--innodb-buffer-pool-size` 를 `command` 로 넘기거나 my.cnf 를 마운트해야 한다.

**② `ignore_changes = [task_definition]` 때문에 태스크 정의 변경이 조용히 배포되지 않는다**

`aws_ecs_service.mysql_service` 에 `lifecycle { ignore_changes = [task_definition, desired_count] }`
가 걸려 있다. **태스크 정의를 고치면 새 리비전만 만들어지고 서비스는 옛 리비전을 계속 돌린다.**
`terraform plan` 은 성공하는데 실물은 안 바뀌므로 조용히 어긋난다 —
rev 40 이 (2026-08-20 부터 8-31 까지) 고정돼 있던 것도 이 때문이다.

| 서비스 | `ignore_changes` | 정당한가 |
|---|---|---|
| dev-api · prod-api | `[task_definition, load_balancer]` | ✅ CodeDeploy 소유. **단 위 11번 단계의 원인이다** |
| **dev-mysql** | `[task_definition, desired_count]` | ❌ 이 Phase 에서 서비스째 제거되므로 자연 해소 |
| **prod-redis** | `[task_definition, desired_count]` | ❌ **남는다 — 아래 참조** |
| dev-redis | 없음 | — [9](./phase-09-dev-cache-asg.md) 에서 제거 |

> 🔴 **prod-redis 에도 같은 함정이 있다.** [Phase 7](./phase-07-elasticache.md) 에서 ElastiCache 로
> 이관하며 서비스가 제거될 때까지, **prod Redis 태스크 정의를 고쳐도 배포되지 않는다.**
> 급히 고쳐야 할 일이 생기면 `aws ecs update-service --force-new-deployment --task-definition <family>:<rev>`
> 로 강제 배포해야 한다. Redis 컨테이너 재시작은 결제 멱등성 키·재고 예약 유실로 직결되므로
> (CLAUDE.md 의 Redis 표 참조) 이 사실을 모르고 "고쳤는데 왜 그대로지"를 반복하는 상황이 가장 위험하다.

---

[← Phase 8 — Prod ASG 전환](./phase-08-prod-asg.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 9 — Dev ElastiCache + ASG →](./phase-09-dev-cache-asg.md)
