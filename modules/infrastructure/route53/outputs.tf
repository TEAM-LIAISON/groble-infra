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

output "internal_zone_id" {
  description = "ID of the internal (VPC-only) hosted zone"
  value       = aws_route53_zone.internal.zone_id
}

output "otel_endpoint_fqdn" {
  description = "앱의 OTEL_EXPORTER_OTLP_ENDPOINT 에 넣을 호스트명"
  value       = aws_route53_record.otel_internal.fqdn
}
