# ECS 관련 IAM 역할 출력
output "ecs_instance_role_arn" {
  description = "ARN of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "ecs_instance_role_name" {
  description = "Name of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.name
}

output "ecs_instance_profile_name" {
  description = "Name of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.name
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task_role.name
}

# CodeDeploy 관련 IAM 역할 출력
output "codedeploy_service_role_arn" {
  description = "ARN of the CodeDeploy service role"
  value       = aws_iam_role.codedeploy_service_role.arn
}

output "codedeploy_service_role_name" {
  description = "Name of the CodeDeploy service role"
  value       = aws_iam_role.codedeploy_service_role.name
}
