#################################
# RDS MySQL Instance for Production
#################################

# DB Subnet Group
resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = "${var.project_name}-mysql-subnet-group"
  subnet_ids = var.private_subnet_ids
  
  tags = {
    Name        = "${var.project_name}-mysql-subnet-group"
    Environment = var.environment
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier = "${var.project_name}-${var.environment}-mysql"
  
  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class
  
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
  parameter_group_name = aws_db_parameter_group.mysql_params.name
  
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
resource "aws_db_parameter_group" "mysql_params" {
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
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-mysql-84-params"
    Environment = var.environment
  }
}