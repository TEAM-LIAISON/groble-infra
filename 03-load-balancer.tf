#################################
# Application Load Balancer
#################################

resource "aws_lb" "groble_load_balancer" {
  name               = "${var.project_name}-load-balancer"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4" 
  security_groups    = [aws_security_group.groble_load_balancer_sg.id]
  subnets           = aws_subnet.groble_vpc_public[*].id

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true

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
  vpc_id      = aws_vpc.groble_vpc.id
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
  vpc_id      = aws_vpc.groble_vpc.id
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
  vpc_id      = aws_vpc.groble_vpc.id
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
  vpc_id      = aws_vpc.groble_vpc.id
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
  vpc_id      = aws_vpc.groble_vpc.id
  target_type = "instance"

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
}

# 추가 인증서 연결 (변수가 설정되어 있을 때만 생성)
resource "aws_lb_listener_certificate" "groble_additional_cert" {
  count           = var.additional_ssl_certificate_arn != "" ? 1 : 0
  listener_arn    = aws_lb_listener.groble_https_listener.arn
  certificate_arn = var.additional_ssl_certificate_arn
}

# 추가 인증서를 테스트 리스너에도 연결
resource "aws_lb_listener_certificate" "groble_additional_cert_test" {
  count           = var.additional_ssl_certificate_arn != "" ? 1 : 0
  listener_arn    = aws_lb_listener.groble_https_test_listener.arn
  certificate_arn = var.additional_ssl_certificate_arn
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

# API 테스트 운영 라우팅 규칙 (api.groble.im → Production Blue)
resource "aws_lb_listener_rule" "api_test_production_rule" {
  listener_arn = aws_lb_listener.groble_https_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Production Rule"
    Environment = "production"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# API 테스트 개발 라우팅 규칙 (api.dev.groble.im → Development Blue)
resource "aws_lb_listener_rule" "api_test_development_rule" {
  listener_arn = aws_lb_listener.groble_https_listener.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.dev.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Development Rule"
    Environment = "development"
    Project     = var.project_name
    ManagedBy   = "Terraform"
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
}

#################################
# Test 리스너용 라우팅 규칙 (9443 포트)
#################################

# API 테스트 운영 - 테스트 리스너 규칙 (api.groble.im:9443 → Production Green)
resource "aws_lb_listener_rule" "api_test_production_test_rule" {
  listener_arn = aws_lb_listener.groble_https_test_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Production Test Rule"
    Environment = "production"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# API 테스트 개발 - 테스트 리스너 규칙 (api.dev.groble.im:9443 → Development Blue)
resource "aws_lb_listener_rule" "api_test_development_test_rule" {
  listener_arn = aws_lb_listener.groble_https_test_listener.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
  }

  condition {
    host_header {
      values = ["api.dev.groble.im"]
    }
  }

  tags = {
    Name        = "API Test Development Test Rule"
    Environment = "development"
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}