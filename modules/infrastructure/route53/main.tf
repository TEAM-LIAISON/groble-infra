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

#################################
# MCP 도메인 레코드
#################################
# api.* 와 같은 ALB 를 가리킨다. 새 대상 그룹 없이 ALB 호스트 헤더 규칙으로만 갈린다.

# MCP 운영 도메인 (mcp.groble.im)
resource "aws_route53_record" "mcp_production" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "mcp.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

# MCP 개발 도메인 (mcp.dev.groble.im)
resource "aws_route53_record" "mcp_development" {
  zone_id = data.aws_route53_zone.groble_zone.zone_id
  name    = "mcp.dev.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

#################################
# 내부 DNS (Phase 4 — 모니터링 노드 재구축)
#################################
# 앱 설정에 모니터링 노드의 raw IP 를 넣지 않기 위한 private hosted zone 이다 (계획서 §2.4).
#
# 지금은 앱의 OTLP 엔드포인트에 노드 사설 IP 가 그대로 박혀 있어, 노드를 교체하려면
# 앱을 재배포해야 한다. 이름으로 바꿔 두면 이후 교체는 **레코드 값 변경으로 끝난다.**
#
# 이 zone 은 VPC 안에서만 해석된다. 공개 groble.im zone 과 충돌하지 않고 위임도 필요 없다.
# 비용은 월 ~$0.5 다.

resource "aws_route53_zone" "internal" {
  name    = "internal.${var.domain_name}"
  comment = "Internal service discovery (VPC-only). Phase 4."

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "internal-${var.domain_name}"
  }
}

# otel.internal.groble.im → 모니터링 노드 사설 IP
#
# ⚠️ TTL 60 초는 이 레코드의 존재 이유다. 노드를 바꿀 때 60 초 안에 트래픽이 옮겨가야 한다.
#    길게 두면 간접화의 의미가 사라지므로 올리지 말 것.
#
# 전환(Phase 4 F단계): var.otel_target_private_ip 를 신 노드 IP 로 바꾸면 된다.
#    앱 재배포는 필요 없다 — 단, JVM 의 networkaddress.cache.ttl 이 유한해야 한다
#    (2026-08-29 RDS 전환 때 JVM 이 구 IP 를 붙잡아 7~8분 쓰기가 실패한 전력이 있다).
#    요청서: docs/handoff/rolling-deploy-prerequisites.md 문항 9·10
resource "aws_route53_record" "otel_internal" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "otel.internal.${var.domain_name}"
  type    = "A"
  ttl     = 60

  records = [var.otel_target_private_ip]
}
