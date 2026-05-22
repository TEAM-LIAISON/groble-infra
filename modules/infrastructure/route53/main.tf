#################################
# Route 53 DNS Records
#################################

# Route 53 호스티드 존 참조
data "aws_route53_zone" "groble_zone" {
  name = var.domain_name
}

#################################
# API 테스트 도메인 레코드
#################################

# API 테스트 운영 도메인 (api.groble.im)
resource "aws_route53_record" "api_test_production" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

# API 테스트 개발 도메인 (dev.groble.im)
resource "aws_route53_record" "api_test_development" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "api.dev.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

# CAA 레코드 - api.dev.groble.im (Amazon 인증서 발급 허용)
resource "aws_route53_record" "api_dev_caa" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "api.dev.${var.domain_name}"
  type    = "CAA"
  ttl     = 300

  records = [
    "0 issue \"amazon.com\""
  ]
}

# 모니터링 도메인 (monitor.groble.im)
resource "aws_route53_record" "monitoring" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "monitor.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}
