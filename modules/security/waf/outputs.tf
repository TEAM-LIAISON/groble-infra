#################################
# WAF Outputs
#################################

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.groble_waf.arn
}

output "web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.groble_waf.id
}

output "web_acl_name" {
  description = "Name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.groble_waf.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for WAF"
  value       = aws_cloudwatch_log_group.waf_log_group.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for WAF"
  value       = aws_cloudwatch_log_group.waf_log_group.arn
}