output "rds_endpoint" {
  description = "The RDS instance endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_address" {
  description = "The RDS instance address"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "The RDS instance port"
  value       = aws_db_instance.mysql.port
}

output "rds_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.mysql.id
}

output "rds_arn" {
  description = "The RDS instance ARN"
  value       = aws_db_instance.mysql.arn
}

output "database_name" {
  description = "The database name"
  value       = aws_db_instance.mysql.db_name
}

output "database_username" {
  description = "The database username"
  value       = aws_db_instance.mysql.username
  sensitive   = true
}