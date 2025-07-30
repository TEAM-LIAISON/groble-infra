#################################
# Route 53 DNS Records
#################################

# Route 53 호스티드 존 참조
data "aws_route53_zone" "groble_zone" {
  name = "groble.im"
}

#################################
# API 테스트 도메인 레코드
#################################

# API 테스트 운영 도메인 (apitest.groble.im)
resource "aws_route53_record" "api_test_production" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "apitest.groble.im"
  type    = "A"

  alias {
    name                   = aws_lb.groble_load_balancer.dns_name
    zone_id                = aws_lb.groble_load_balancer.zone_id
    evaluate_target_health = true
  }
}

# API 테스트 개발 도메인 (apidev.groble.im)
resource "aws_route53_record" "api_test_development" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "apidev.groble.im"
  type    = "A"

  alias {
    name                   = aws_lb.groble_load_balancer.dns_name
    zone_id                = aws_lb.groble_load_balancer.zone_id
    evaluate_target_health = true
  }
}
