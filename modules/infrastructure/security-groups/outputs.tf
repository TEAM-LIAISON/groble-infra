# 로드 밸런서 보안 그룹 출력
output "load_balancer_sg_id" {
  description = "ID of the load balancer security group"
  value       = aws_security_group.groble_load_balancer_sg.id
}

# 프로덕션 보안 그룹 출력
output "prod_target_group_sg_id" {
  description = "ID of the production target group security group"
  value       = aws_security_group.groble_prod_target_group.id
}

# 개발 보안 그룹 출력
output "develop_target_group_sg_id" {
  description = "ID of the development target group security group"
  value       = aws_security_group.groble_develop_target_group.id
}

# 모니터링 보안 그룹 출력
output "monitor_target_group_sg_id" {
  description = "ID of the monitoring target group security group"
  value       = aws_security_group.groble_monitor_target_group.id
}

# API 태스크 보안 그룹 출력
output "api_task_sg_id" {
  description = "ID of the API task security group"
  value       = aws_security_group.groble_api_task_sg.id
}

# 모든 보안 그룹 ID 리스트
output "all_security_group_ids" {
  description = "List of all security group IDs"
  value = [
    aws_security_group.groble_load_balancer_sg.id,
    aws_security_group.groble_prod_target_group.id,
    aws_security_group.groble_develop_target_group.id,
    aws_security_group.groble_monitor_target_group.id,
    aws_security_group.groble_api_task_sg.id
  ]
}
