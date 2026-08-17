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
  description = <<-EOT
    RDS 리소스 ID (`db-XXXXXXXX` 형식).

    ⚠️ **CloudWatch 차원 값이 아니다.** AWS provider 5.x의 `aws_db_instance.id`는
    DBInstanceIdentifier가 아니라 DbiResourceId를 반환한다.
    CloudWatch 알람에는 아래 `rds_instance_identifier`를 쓸 것 —
    이 값을 쓰면 존재하지 않는 지표를 감시하게 되어 알람이 영원히
    INSUFFICIENT_DATA에 머문다 (에러 없이 조용히 실패한다).
  EOT
  value       = aws_db_instance.mysql.id
}

output "rds_instance_identifier" {
  description = "RDS 인스턴스 식별자 (`groble-prod-mysql` 형식). CloudWatch `DBInstanceIdentifier` 차원 값"
  value       = aws_db_instance.mysql.identifier
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