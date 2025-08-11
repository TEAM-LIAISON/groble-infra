# Load Balancer 출력
output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.groble_load_balancer.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.groble_load_balancer.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.groble_load_balancer.zone_id
}

# Target Group 출력
output "prod_blue_target_group_arn" {
  description = "ARN of the production blue target group"
  value       = aws_lb_target_group.groble_prod_blue_tg.arn
}

output "prod_blue_target_group_name" {
  description = "Name of the production blue target group"
  value       = aws_lb_target_group.groble_prod_blue_tg.name
}

output "prod_green_target_group_arn" {
  description = "ARN of the production green target group"
  value       = aws_lb_target_group.groble_prod_green_tg.arn
}

output "prod_green_target_group_name" {
  description = "Name of the production green target group"
  value       = aws_lb_target_group.groble_prod_green_tg.name
}

output "dev_blue_target_group_arn" {
  description = "ARN of the development blue target group"
  value       = aws_lb_target_group.groble_dev_blue_tg.arn
}

output "dev_blue_target_group_name" {
  description = "Name of the development blue target group"
  value       = aws_lb_target_group.groble_dev_blue_tg.name
}

output "dev_green_target_group_arn" {
  description = "ARN of the development green target group"
  value       = aws_lb_target_group.groble_dev_green_tg.arn
}

output "dev_green_target_group_name" {
  description = "Name of the development green target group"
  value       = aws_lb_target_group.groble_dev_green_tg.name
}

output "monitoring_target_group_arn" {
  description = "ARN of the monitoring target group"
  value       = aws_lb_target_group.groble_monitoring_tg.arn
}

# Listener 출력
output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.groble_https_listener.arn
}

output "https_test_listener_arn" {
  description = "ARN of the HTTPS test listener"
  value       = aws_lb_listener.groble_https_test_listener.arn
}
