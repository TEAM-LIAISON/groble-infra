# Route53 관련 출력
output "hosted_zone_id" {
  description = "ID of the Route53 hosted zone"
  value       = data.aws_route53_zone.groble_zone.zone_id
}

output "api_production_fqdn" {
  description = "FQDN for API production domain"
  value       = aws_route53_record.api_test_production.fqdn
}

output "api_development_fqdn" {
  description = "FQDN for API development domain"
  value       = aws_route53_record.api_test_development.fqdn
}

output "mcp_production_fqdn" {
  description = "FQDN for MCP production domain"
  value       = aws_route53_record.mcp_production.fqdn
}

output "mcp_development_fqdn" {
  description = "FQDN for MCP development domain"
  value       = aws_route53_record.mcp_development.fqdn
}
