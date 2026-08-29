#################################
# Groble Infrastructure - Shared Environment
#################################
# 
# 이 파일은 groble 애플리케이션의 공유 인프라를 위한 Terraform 설정입니다.
# DEV와 PROD 환경에서 공통으로 사용하는 리소스들을 관리합니다.
# 
# 공유 리소스:
# - Infrastructure Layer: VPC, 네트워크, 보안 그룹, Load Balancer, IAM 역할, Route53
# - Platform Layer: ECS Cluster, CodeDeploy
# - Observability: 알람 통지 경로(SNS/Slack) 및 ALB 알람

#################################
# Infrastructure Layer 모듈 호출
#################################

# 현재 계정 ID (SNS 토픽 정책의 SourceAccount 조건에 사용)
data "aws_caller_identity" "current" {}

# VPC 및 네트워크 인프라
module "vpc" {
  source = "../../modules/infrastructure/vpc"

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  project_name         = var.project_name
  nat_gateway_az       = var.nat_gateway_az

  # Phase 3 — 생성/전환 스위치
  create_nat_gateway               = var.create_nat_gateway
  attach_s3_endpoint_to_private_rt = var.attach_s3_endpoint_to_private_rt
}

# 보안 그룹 인프라
module "security_groups" {
  source = "../../modules/infrastructure/security-groups"

  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  project_name = var.project_name
  trusted_ips  = var.trusted_ips
}

# IAM 역할 인프라
module "iam_roles" {
  source = "../../modules/infrastructure/iam-roles"

  project_name = var.project_name
}

# Load Balancer 인프라
module "load_balancer" {
  source = "../../modules/infrastructure/load-balancer"

  vpc_id                         = module.vpc.vpc_id
  public_subnet_ids              = module.vpc.public_subnet_ids
  load_balancer_sg_id            = module.security_groups.load_balancer_sg_id
  project_name                   = var.project_name
  enable_deletion_protection     = var.enable_deletion_protection
  health_check_path              = var.health_check_path
  ssl_certificate_arn            = var.ssl_certificate_arn
  additional_ssl_certificate_arn = aws_acm_certificate_validation.dev_wildcard.certificate_arn
  extra_ssl_certificate_arns     = [aws_acm_certificate_validation.mcp_dev.certificate_arn]
  idle_timeout                   = 300
}

# Route53 DNS 인프라
module "route53" {
  source = "../../modules/infrastructure/route53"

  load_balancer_dns_name = module.load_balancer.load_balancer_dns_name
  load_balancer_zone_id  = module.load_balancer.load_balancer_zone_id
}

#################################
# ACM 인증서 - *.dev.groble.im
#################################

resource "aws_acm_certificate" "dev_wildcard" {
  domain_name       = "api.dev.groble.im"
  validation_method = "DNS"

  tags = {
    Name = "api-dev-groble-im"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "dev_wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.dev_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = module.route53.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "dev_wildcard" {
  certificate_arn         = aws_acm_certificate.dev_wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.dev_wildcard_validation : record.fqdn]
}

#################################
# ACM 인증서 - mcp.dev.groble.im
#################################
# mcp.groble.im 은 리스너에 이미 붙어 있는 *.groble.im 와일드카드로 커버된다.
# 와일드카드는 한 단계만 매칭하므로 mcp.dev.groble.im 은 커버되지 않아 단일 SAN 인증서를 따로 발급한다.
# (api.dev.groble.im 이 이미 같은 방식이다)

# CAA 레코드 - mcp.dev.groble.im (Amazon 인증서 발급 허용)
#
# ⚠️ 이 레코드가 없으면 ACM 발급이 실패한다. mcp.dev.groble.im 에 CAA 가 없으면
#    상위 dev.groble.im 으로 올라가는데, dev.groble.im 은 Vercel(cname.vercel-dns.com)로 가는
#    CNAME 이고 그쪽 CAA 는 sectigo/pki.goog/globalsign/letsencrypt 만 허용한다 — amazon.com 이 없다.
#    api.dev.groble.im 에 CAA 가 따로 박혀 있는 것도 같은 이유다.
resource "aws_route53_record" "mcp_dev_caa" {
  zone_id = module.route53.hosted_zone_id
  name    = "mcp.dev.groble.im"
  type    = "CAA"
  ttl     = 300

  records = [
    "0 issue \"amazon.com\""
  ]

  allow_overwrite = true
}

resource "aws_acm_certificate" "mcp_dev" {
  domain_name       = "mcp.dev.groble.im"
  validation_method = "DNS"

  tags = {
    Name = "mcp-dev-groble-im"
  }

  lifecycle {
    create_before_destroy = true
  }

  # CAA 가 먼저 올라간 뒤에 발급을 요청해야 한다 (위 주석 참고)
  depends_on = [aws_route53_record.mcp_dev_caa]
}

resource "aws_route53_record" "mcp_dev_validation" {
  for_each = {
    for dvo in aws_acm_certificate.mcp_dev.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = module.route53.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "mcp_dev" {
  certificate_arn         = aws_acm_certificate.mcp_dev.arn
  validation_record_fqdns = [for record in aws_route53_record.mcp_dev_validation : record.fqdn]
}

# WAF 보안 인프라
module "waf" {
  source = "../../modules/security/waf"

  project_name      = var.project_name
  environment       = var.environment
  load_balancer_arn = module.load_balancer.load_balancer_arn

  # Geo-blocking 설정 (기본값: 아시아-태평양 지역)
  allowed_country_codes = var.allowed_country_codes

  # Rate limiting 설정
  rate_limit_per_ip          = var.rate_limit_per_ip
  rate_limit_global          = var.rate_limit_global
  rate_limit_login_endpoints = var.rate_limit_login_endpoints

  # Request size 설정
  max_request_size = var.max_request_size
}


#################################
# Platform Layer 모듈 호출
#################################

# ECS 클러스터 플랫폼 (공통 인프라만)
module "ecs_cluster" {
  source = "../../modules/platform/ecs-cluster"

  project_name              = var.project_name
  enable_container_insights = false

  # CloudWatch Logs 설정 (비활성화)
  create_prod_logs        = false
  create_dev_logs         = false
  prod_log_retention_days = 7
  dev_log_retention_days  = 3

  # Instance 생성 설정
  create_prod_instance       = true
  create_monitoring_instance = true
  create_dev_instance        = true

  # Instance 구성
  prod_instance_count      = var.prod_instance_count
  prod_instance_type       = var.prod_instance_type
  monitoring_instance_type = var.monitoring_instance_type
  dev_instance_type        = var.dev_instance_type
  key_pair_name            = var.key_pair_name

  # VPC 및 네트워크
  ubuntu_ami_id      = module.vpc.ubuntu_ami_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Security Groups
  prod_security_group_id       = module.security_groups.prod_target_group_sg_id
  monitoring_security_group_id = module.security_groups.monitor_target_group_sg_id
  dev_security_group_id        = module.security_groups.develop_target_group_sg_id

  # IAM
  ecs_instance_profile_name = module.iam_roles.ecs_instance_profile_name

  # Load Balancer
  monitoring_target_group_arn = module.load_balancer.monitoring_target_group_arn

  # Route Tables
  private_route_table_id = module.vpc.private_route_table_id

  # Phase 3 — 기본 경로 타깃. use_nat_gateway 를 true 로 바꾸는 순간 전환된다
  nat_gateway_id  = module.vpc.nat_gateway_id
  use_nat_gateway = var.use_nat_gateway
}

#################################
# CodeDeploy 배포 서비스 (공통 설정)
#################################

module "codedeploy" {
  source = "../../modules/platform/codedeploy"

  project_name                 = var.project_name
  create_prod_deployment_group = true
  create_dev_deployment_group  = true
  create_artifacts_bucket      = true

  # IAM Role
  codedeploy_service_role_arn = module.iam_roles.codedeploy_service_role_arn

  # ECS 설정
  ecs_cluster_name  = module.ecs_cluster.cluster_name
  prod_service_name = "${var.project_name}-prod-service"
  dev_service_name  = "${var.project_name}-dev-service"

  # Deployment Configuration
  prod_deployment_config = var.prod_deployment_config
  dev_deployment_config  = var.dev_deployment_config

  # Blue/Green 배포 설정
  deployment_ready_timeout_action = var.deployment_ready_timeout_action
  deployment_ready_wait_time      = var.deployment_ready_wait_time
  termination_wait_time           = var.termination_wait_time

  # Load Balancer 설정
  prod_blue_target_group_name  = module.load_balancer.prod_blue_target_group_name
  prod_green_target_group_name = module.load_balancer.prod_green_target_group_name
  dev_blue_target_group_name   = module.load_balancer.dev_blue_target_group_name
  dev_green_target_group_name  = module.load_balancer.dev_green_target_group_name
  prod_listener_arns           = [module.load_balancer.https_listener_arn]
  test_listener_arns           = [module.load_balancer.https_test_listener_arn]

  # 자동 롤백 설정
  enable_auto_rollback = var.enable_auto_rollback
  auto_rollback_events = var.auto_rollback_events

}

# ---------------------------------------------------------------------------
# Phase 1 — 알람 백스톱
#
# 자체 호스팅 관측 스택(모니터링 노드) 바깥의 알림 경로.
# 그 노드가 죽어도 알림은 도달해야 하므로 AWS 관리형 구성요소만 사용한다.
#
# 채널을 긴급도로 나눈다 — 볼륨 때문이 아니라, "새벽에 깨야 하는 것"과
# "내일 봐도 되는 것"이 같은 채널에 있으면 구분이 안 되기 때문이다.
#
# 상세: docs/runbook/phase-01-alarm-backstop.md
# ---------------------------------------------------------------------------

# 즉시 대응이 필요한 알림 (#groble-alert)
module "alerting_prod" {
  source = "../../modules/observability/alerting"

  # Chatbot API는 us-east-2에만 엔드포인트가 있다 (모듈 versions.tf 참조)
  providers = {
    aws         = aws
    aws.chatbot = aws.chatbot
  }

  project_name   = var.project_name
  name_suffix    = "prod"
  aws_account_id = data.aws_caller_identity.current.account_id

  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id_prod
}

# 업무 시간에 확인하면 되는 알림 (#groble-alert-dev)
module "alerting_dev" {
  source = "../../modules/observability/alerting"

  providers = {
    aws         = aws
    aws.chatbot = aws.chatbot
  }

  project_name   = var.project_name
  name_suffix    = "dev"
  aws_account_id = data.aws_caller_identity.current.account_id

  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id_dev
}

module "alb_alarms" {
  source = "../../modules/observability/alb-alarms"

  project_name   = var.project_name
  alb_arn_suffix = module.load_balancer.load_balancer_arn_suffix

  services = {
    # Blue/Green은 배포마다 활성 TG가 뒤바뀌므로 양쪽을 함께 넘긴다.
    prod = {
      target_groups = [
        module.load_balancer.prod_blue_target_group_arn_suffix,
        module.load_balancer.prod_green_target_group_arn_suffix,
      ]
      alarm_actions = [module.alerting_prod.sns_topic_arn]
      ok_actions    = [module.alerting_prod.sns_topic_arn]

      # prod의 500은 단 한 건도 넘기지 않는다 (기본값 10 대신 1).
      # 실측 기준선으로 잡은 10은 "5분에 10건 미만이면 무시"라는 뜻이었고,
      # 그래서 2026-08-17 20:04 KST `POST /api/v1/market/edit` 500 2건이
      # 아무 데도 알려지지 않았다. dev는 개발 중 500이 흔하므로 10을 유지한다.
      target_5xx_threshold = 1
    }

    # dev는 ok_actions를 걸지 않는다 — 사건당 메시지가 2배가 되는 것을
    # 감수할 만큼 급하지 않다. 복구 여부는 필요할 때 콘솔/CLI로 본다.
    dev = {
      target_groups = [
        module.load_balancer.dev_blue_target_group_arn_suffix,
        module.load_balancer.dev_green_target_group_arn_suffix,
      ]
      alarm_actions = [module.alerting_dev.sns_topic_arn]
    }

    # ⚠️ 모니터링 노드는 dev가 아니라 prod 채널로 보낸다.
    #    이 노드가 private 서브넷의 NAT을 겸직하고 있어, 죽으면 prod의
    #    아웃바운드와 ECR pull이 함께 끊긴다. 지금은 prod-critical이다.
    #    Phase 3(NAT Gateway)·Phase 5(노드 재구축) 이후 dev 채널로 내린다.
    #
    #    사용자 트래픽을 받지 않으므로 5xx·지연 알람은 만들지 않는다.
    monitoring = {
      target_groups  = [module.load_balancer.monitoring_target_group_arn_suffix]
      alarm_actions  = [module.alerting_prod.sns_topic_arn]
      ok_actions     = [module.alerting_prod.sns_topic_arn]
      traffic_alarms = false
    }
  }

  # ALB 전체 5xx는 TargetGroup 차원이 없어 prod/dev 분리가 불가능하다.
  # 가장 심각도가 높은 채널로 보낸다 (모듈 변수 주석 참조).
  elb_level_alarm_actions = [module.alerting_prod.sns_topic_arn]
  elb_level_ok_actions    = [module.alerting_prod.sns_topic_arn]
}
