#################################
# Application Load Balancer
#################################

resource "aws_lb" "groble_load_balancer" {
  name               = "${var.project_name}-load-balancer"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4" 
  security_groups    = [var.load_balancer_sg_id]
  subnets           = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true
  idle_timeout               = var.idle_timeout

  tags = {
    Name = "${var.project_name}-load-balancer"
  }
}

#################################
# Blue/Green Target Groups - Production
#################################

# Production Blue Target Group
resource "aws_lb_target_group" "groble_prod_blue_tg" {
  name        = "${var.project_name}-prod-blue-tg-v2"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # awsvpc mode support

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name                  = "${var.project_name}-prod-blue-tg"
    Environment          = "production"
    Color                = "blue"
    CodeDeployApplication = "groble-app"
  }
}

# Production Green Target Group
resource "aws_lb_target_group" "groble_prod_green_tg" {
  name        = "${var.project_name}-prod-green-tg-v2"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # awsvpc mode support

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name                  = "${var.project_name}-prod-green-tg"
    Environment          = "production"
    Color                = "green"
    CodeDeployApplication = "groble-app"
  }
}

#################################
# Blue/Green Target Groups - Development
#################################

# Development Blue Target Group
resource "aws_lb_target_group" "groble_dev_blue_tg" {
  name        = "${var.project_name}-dev-blue-tg-v2"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # awsvpc mode support

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 8
    unhealthy_threshold = 5
  }

  tags = {
    Name                  = "${var.project_name}-dev-blue-tg"
    Environment          = "development"
    Color                = "blue"
    CodeDeployApplication = "groble-app"
  }
}

# Development Green Target Group
resource "aws_lb_target_group" "groble_dev_green_tg" {
  name        = "${var.project_name}-dev-green-tg-v2"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # awsvpc mode support

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 8
    unhealthy_threshold = 5
  }

  tags = {
    Name                  = "${var.project_name}-dev-green-tg"
    Environment          = "development"
    Color                = "green"
    CodeDeployApplication = "groble-app"
  }
}

#################################
# Monitoring Target Group (단일 - Blue/Green 불필요)
#################################

resource "aws_lb_target_group" "groble_monitoring_tg" {
  name        = "${var.project_name}-monitoring-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # ⚠️ 모니터링 스택은 host 모드 네트워킹이라 포트가 겹친다 — ECS 는 구 태스크가
  #    완전히 빠질 때까지 신 태스크를 배치하지 못한다. 기본값 300초에서는
  #    이미지를 올릴 때마다 관측이 그만큼 통째로 끊긴다.
  #    2026-08-30 Grafana 배포(11.6.3-ddfe23a → 7bc5e87)에서 실제로 약 6분
  #    (00:41:26~00:47:33) 내려가 있었다.
  #    사용자 트래픽을 받지 않으므로 길게 드레이닝할 이유가 없다.
  #
  #    ⚠️ API 타깃그룹에는 손대지 않았다. 그쪽의 300초는 낭비가 아니라 실제
  #       in-flight 드레이닝 시간이다(태스크는 DEACTIVATING 동안 살아 있다).
  #       prod 는 단일 요청 최대 16.7초가 실측되므로 별도 판단이 필요하다.
  deregistration_delay = var.monitoring_deregistration_delay

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/api/health"  # 모니터링 도구 전용 헬스체크
    port                = "3000"         # 고정 포트 (Grafana 등)
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-monitoring-tg"
    Environment = "monitoring"
  }
}

#################################
# ALB 리스너
#################################

# HTTP 리스너 - HTTPS로 리다이렉트
resource "aws_lb_listener" "groble_http_listener" {
  load_balancer_arn = aws_lb.groble_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS 리스너 - 기본적으로 Production Blue로 트래픽 전달
resource "aws_lb_listener" "groble_https_listener" {
  load_balancer_arn = aws_lb.groble_load_balancer.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn  # SSL 인증서 ARN을 변수로 받음

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn  # 초기는 Blue 환경
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [default_action[0].target_group_arn]
  }
}

# 추가 인증서 연결
resource "aws_lb_listener_certificate" "groble_additional_cert" {
  listener_arn    = aws_lb_listener.groble_https_listener.arn
  certificate_arn = var.additional_ssl_certificate_arn
}

# 추가 인증서를 테스트 리스너에도 연결
resource "aws_lb_listener_certificate" "groble_additional_cert_test" {
  listener_arn    = aws_lb_listener.groble_https_test_listener.arn
  certificate_arn = var.additional_ssl_certificate_arn
}

# 호스트 추가로 늘어나는 인증서들 (예: mcp.dev.groble.im). 443·9443 양쪽에 같이 붙인다.
# for_each 가 아니라 count 를 쓰는 이유: 신규 발급 인증서의 ARN 은 apply 전까지 알 수 없어
# for_each 키로 쓸 수 없다. 목록 길이는 plan 시점에 확정되므로 count 는 문제없다.
resource "aws_lb_listener_certificate" "groble_extra_certs" {
  count = length(var.extra_ssl_certificate_arns)

  listener_arn    = aws_lb_listener.groble_https_listener.arn
  certificate_arn = var.extra_ssl_certificate_arns[count.index]
}

resource "aws_lb_listener_certificate" "groble_extra_certs_test" {
  count = length(var.extra_ssl_certificate_arns)

  listener_arn    = aws_lb_listener.groble_https_test_listener.arn
  certificate_arn = var.extra_ssl_certificate_arns[count.index]
}

#################################
# ALB 라우팅 규칙
#################################

# 모니터링 라우팅 규칙 (호스트 기반)
resource "aws_lb_listener_rule" "monitoring_rule" {
  listener_arn = aws_lb_listener.groble_https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_monitoring_tg.arn
  }

  condition {
    host_header {
      values = ["monitor.groble.im"]
    }
  }
}

# 운영 라우팅 규칙 (api.groble.im · mcp.groble.im → Production Blue)
resource "aws_lb_listener_rule" "api_test_production_rule" {
  listener_arn = aws_lb_listener.groble_https_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.groble.im", "mcp.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Production Rule"
    Environment = "production"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [action[0].target_group_arn]
  }
}

# 개발 라우팅 규칙 (api.dev.groble.im · mcp.dev.groble.im → Development Blue)
resource "aws_lb_listener_rule" "api_test_development_rule" {
  listener_arn = aws_lb_listener.groble_https_listener.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.dev.groble.im", "mcp.dev.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Development Rule"
    Environment = "development"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [action[0].target_group_arn]
  }
}

#################################
# ALB Test 리스너
#################################

# HTTPS 테스트 리스너 - CodeDeploy용
resource "aws_lb_listener" "groble_https_test_listener" {
  load_balancer_arn = aws_lb.groble_load_balancer.arn
  port              = 9443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [default_action[0].target_group_arn]
  }
}

#################################
# Test 리스너용 라우팅 규칙 (9443 포트)
#################################

# 운영 - 테스트 리스너 규칙 (api.groble.im · mcp.groble.im:9443 → Production Blue)
resource "aws_lb_listener_rule" "api_test_production_test_rule" {
  listener_arn = aws_lb_listener.groble_https_test_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.groble.im", "mcp.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Production Test Rule"
    Environment = "production"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [action[0].target_group_arn]
  }
}

# 개발 - 테스트 리스너 규칙 (api.dev.groble.im · mcp.dev.groble.im:9443 → Development Blue)
resource "aws_lb_listener_rule" "api_test_development_test_rule" {
  listener_arn = aws_lb_listener.groble_https_test_listener.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.dev.groble.im", "mcp.dev.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Development Test Rule"
    Environment = "development"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  # CodeDeploy Blue/Green 배포가 target_group_arn을 관리하므로 Terraform은 무시
  lifecycle {
    ignore_changes = [action[0].target_group_arn]
  }
}
