#################################
# RDS MySQL Instance for Production
#################################

# DB Subnet Group
# ⚠️ 이름에 environment 가 들어가지 않는다 — 파라미터 그룹과 다르다.
# prod 가 이미 "groble-mysql-subnet-group" 을 쓰고 있어 기본값을 바꿀 수 없다
# (이름은 force-new 속성이라 replace → 붙어 있는 RDS 수정까지 딸려 온다).
# 신규 환경은 var.db_subnet_group_name 으로 다른 이름을 넘긴다.
locals {
  db_subnet_group_name = coalesce(var.db_subnet_group_name, "${var.project_name}-mysql-subnet-group")
}

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = local.db_subnet_group_name
  subnet_ids = var.private_subnet_ids
  
  tags = {
    Name        = local.db_subnet_group_name
    Environment = var.environment
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier = "${var.project_name}-${var.environment}-mysql"
  
  # Engine configuration
  #
  # 2026-08-29 Blue/Green 으로 8.0 → 8.4 전환 완료. 전환은 CLI 로 수행했고
  # 그 뒤 state rm → import 로 신규 인스턴스를 다시 붙였다.
  # state 가 identifier 가 아니라 DbiResourceId 로 추적하기 때문에
  # 코드만 고쳐서는 구 인스턴스를 계속 관리하게 된다.
  # 절차: docs/runbook/adhoc/rds-mysql-84-upgrade.md
  # ⚠️ 마이너까지 정확히 고정한다. "8.4" 로 두면 AWS 가 패밀리 기본값(8.4.9)으로
  #    해석해 8.4.11 → 8.4.9 다운그레이드를 시도하고 apply 가 실패한다.
  #    (2026-08-29 실제로 겪었다: InvalidParameterCombination:
  #     Cannot upgrade mysql from 8.4.11 to 8.4.9)
  #    8.0 시절 "8.0" 표기가 통했던 것은 패밀리 기본값이 마침 실제 버전과
  #    같았기 때문일 뿐이다.
  #
  #    auto_minor_version_upgrade 가 켜져 있어 RDS 가 점검창에 마이너를 올리면
  #    plan 에 드리프트로 뜬다. 그때 이 값을 실제 버전으로 올릴 것 —
  #    드리프트가 보이는 편이 조용히 어긋나는 것보다 낫다.
  engine                      = "mysql"
  engine_version              = "8.4.11"
  allow_major_version_upgrade = true
  instance_class              = var.instance_class
  
  # Database configuration
  db_name  = var.database_name
  username = var.database_username
  password = var.database_password
  
  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  
  # Availability and scaling
  multi_az               = var.multi_az
  availability_zone      = var.availability_zone
  
  # Monitoring (disabled for budget)
  monitoring_interval = 0
  enabled_cloudwatch_logs_exports = []
  
  # Performance Insights (disabled for budget)
  performance_insights_enabled = false
  
  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-mysql-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # Parameter group
  parameter_group_name = aws_db_parameter_group.mysql_params_84.name
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-mysql"
    Environment = var.environment
    Type        = "database"
  }
  
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [final_snapshot_identifier]
  }
}

# DB Parameter Group for MySQL 8.0
#
# prod 가 8.4 로 올라간 뒤로 아무도 참조하지 않는 잔재다 (인스턴스는 mysql_params_84 를 쓴다).
# state 에 남아 있어 지우지 못하고 있을 뿐이므로 신규 환경은 count = 0 으로 건너뛴다.
# 실제 제거는 Phase 11.
#
# ⚠️ count 를 붙이면서 state 주소가 `...mysql_params` → `...mysql_params[0]` 로 바뀐다.
#    prod 는 apply 전에 반드시 state mv 를 해야 destroy/create 가 계획되지 않는다:
#      terraform state mv 'module.rds_mysql.aws_db_parameter_group.mysql_params' \
#                         'module.rds_mysql.aws_db_parameter_group.mysql_params[0]'
#    (docs/runbook/phase-05-dev-rds.md A단계)
resource "aws_db_parameter_group" "mysql_params" {
  count = var.create_legacy_80_parameter_group ? 1 : 0

  family = "mysql8.0"
  name   = "${var.project_name}-${var.environment}-mysql-params"
  
  # apply_method는 RDS가 실제로 유지하는 값(pending-reboot)에 맞춘다.
  # 이 값은 엔진 기본값과 동일한 수식이라 RDS 쪽에서 no-op 수정으로 처리되며,
  # "immediate"를 선언하면 apply가 성공해도 AWS가 pending-reboot를 유지해
  # plan이 영구히 1건의 변경을 보고한다(perpetual diff).
  parameter {
    name         = "innodb_buffer_pool_size"
    value        = "{DBInstanceClassMemory*3/4}"
    apply_method = "pending-reboot"
  }
  
  parameter {
    name  = "max_connections"
    value = "200"
  }
  
  # RDS Blue/Green 배포의 전제조건이다. 기본값 MIXED로는 그린 인스턴스로의
  # 논리 복제가 성립하지 않아 create-blue-green-deployment가 거부된다.
  # 동적 파라미터라 재부팅 없이 적용된다.
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-mysql-params"
    Environment = var.environment
  }
}

# DB Parameter Group for MySQL 8.4
#
# 8.0용 그룹을 고쳐 쓸 수 없다 — family는 변경 불가 속성이라 in-place 수정이 되지 않고,
# 같은 이름으로 replace를 걸면 destroy와 create가 이름 충돌로 맞물린다.
# 그래서 별도 이름의 신규 리소스로 만든다. 이 리소스는 순수 추가라 기존 인스턴스에
# 아무 영향을 주지 않으며, Blue/Green의 그린 인스턴스가 이것을 받아 기동한다.
#
# 이관 대상은 max_connections 하나뿐이다. innodb_buffer_pool_size는 위 그룹에서도
# 엔진 기본 수식과 동일해 RDS가 user-set으로 잡지 않으므로(--source user 조회 시 미출력)
# 여기로 옮기지 않는다. 옮기면 perpetual diff만 생긴다.
resource "aws_db_parameter_group" "mysql_params_84" {
  family = "mysql8.4"
  name   = "${var.project_name}-${var.environment}-mysql-84-params"
  
  parameter {
    name  = "max_connections"
    value = "200"
  }
  
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }
  
  # ⚠️ 아래 4건은 8.4 로 올리면서 조용히 달라지는 값을 8.0 과 맞추는 것이다.
  #
  # RDS 는 mysql8.4 부터 innodb_dedicated_server 기본값을 1 로 켜고,
  # innodb_buffer_pool_size / innodb_redo_log_capacity 의 기본값을 아예 없앴다.
  # 그러면 MySQL 이 감지 메모리로 자동 계산하는데, db.t3.micro(1 GiB)에서는
  # "1GB 미만" 구간의 최솟값이 잡혀 버퍼풀이 256 MiB → 128 MiB 로 반토막 난다.
  # redo 도 2048 MiB → 1024 MiB 로 줄어든다. (2026-08-28 그린에서 실측)
  #
  # 버전 업그레이드는 like-for-like 여야 한다 — 성능 특성을 같이 바꾸면
  # 전환 후 문제가 생겼을 때 8.4 탓인지 버퍼풀 탓인지 갈리지 않는다.
  # 튜닝이 필요하면 전환이 끝난 뒤 별도로 측정해서 한다.
  #
  # innodb_dedicated_server 가 1 이면 MySQL 이 buffer_pool / redo 를 자동 설정하고
  # 명시값을 무시한다. 그래서 반드시 0 으로 꺼야 아래 두 값이 먹는다.
  parameter {
    name         = "innodb_dedicated_server"
    value        = "0"
    apply_method = "pending-reboot" # static 파라미터
  }
  
  parameter {
    name         = "innodb_buffer_pool_size"
    value        = "{DBInstanceClassMemory*3/4}" # 8.0 기본값과 동일한 수식 → 256 MiB
    apply_method = "pending-reboot"
  }
  
  parameter {
    name  = "innodb_redo_log_capacity"
    value = "2147483648" # 8.0 기본값(2 GiB)과 동일
  }
  
  # 8.0 은 TABLE 이 기본이고 8.4 는 기본값이 없어 FILE 로 떨어진다.
  # general_log·slow_query_log 가 둘 다 꺼져 있어 지금은 무해하지만,
  # 나중에 켤 때 mysql.slow_log 테이블을 보던 사람이 빈 테이블을 보게 된다.
  parameter {
    name  = "log_output"
    value = "TABLE"
  }
  
  # log_error_suppression_list(블루 = MY-013360)는 맞출 수 없다.
  # RDS 가 설정 가능한 파라미터로 노출하지 않는다(8.0·8.4 양쪽 그룹에 없음) —
  # 블루의 값은 RDS 가 내부적으로 넣은 것이다. 8.4 에서는 해당 경고
  # (mysql_native_password deprecated)가 에러 로그에 남게 된다. 기능 영향은 없다.
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-mysql-84-params"
    Environment = var.environment
  }
}