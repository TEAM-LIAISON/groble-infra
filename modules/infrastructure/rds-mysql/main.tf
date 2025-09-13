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
  }
}

# DB Parameter Group for MySQL 8.0
resource "aws_db_parameter_group" "mysql_params" {
  family = "mysql8.0"
  name   = "${var.project_name}-${var.environment}-mysql-params"
  
  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }
  
  parameter {
    name  = "max_connections"
    value = "200"
  }
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-mysql-params"
    Environment = var.environment
  }
}