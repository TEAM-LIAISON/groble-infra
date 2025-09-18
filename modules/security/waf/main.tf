#################################
# Data Sources
#################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#################################
# AWS WAF v2 Web ACL
#################################

resource "aws_wafv2_web_acl" "groble_waf" {
  name        = "${var.project_name}-waf"
  description = "WAF for Groble Application Load Balancer"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # AWS Managed Rules - Core Rule Set
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - SQL Database
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - IP Reputation
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 4

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IpReputationMetric"
      sampled_requests_enabled   = true
    }
  }

  #################################
  # HIGH PRIORITY RULES
  #################################

  # Rate Limiting Rule - Per IP
  rule {
    name     = "RateLimitPerIP"
    priority = 10

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_ip
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string = "/"
            field_to_match {
              uri_path {}
            }
            positional_constraint = "STARTS_WITH"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIPMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rate Limiting Rule - Global
  rule {
    name     = "RateLimitGlobal"
    priority = 11

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_global
        aggregate_key_type = "CONSTANT"

        scope_down_statement {
          byte_match_statement {
            search_string = "/"
            field_to_match {
              uri_path {}
            }
            positional_constraint = "STARTS_WITH"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitGlobalMetric"
      sampled_requests_enabled   = true
    }
  }

  # Spring Boot Actuator Protection - Block public access except health
  rule {
    name     = "BlockActuatorEndpoints"
    priority = 12

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string = "/actuator/"
            field_to_match {
              uri_path {}
            }
            positional_constraint = "CONTAINS"
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              byte_match_statement {
                search_string = "/actuator/health"
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "EXACTLY"
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ActuatorProtectionMetric"
      sampled_requests_enabled   = true
    }
  }

  # Request Size Limiting - Block unusually large requests
  rule {
    name     = "RequestSizeLimit"
    priority = 13

    action {
      count {}
    }

    statement {
      size_constraint_statement {
        field_to_match {
          body {
            oversize_handling = "CONTINUE"
          }
        }
        comparison_operator = "GT"
        size                = var.max_request_size
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RequestSizeLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  #################################
  # MEDIUM PRIORITY RULES
  #################################

  # Geo-blocking Rule - Allow only Korea and Asia-Pacific
  rule {
    name     = "GeoBlockingRule"
    priority = 20

    action {
      count {}
    }

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = var.allowed_country_codes
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlockingMetric"
      sampled_requests_enabled   = true
    }
  }

  # Login Endpoint Brute Force Protection - Rate limiting for login endpoints only
  rule {
    name     = "LoginBruteForceProtection"
    priority = 21

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_login_endpoints
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string = "/login"
            field_to_match {
              uri_path {}
            }
            positional_constraint = "CONTAINS"
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "LoginBruteForceMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics
    metric_name                = "${var.project_name}WAF"
    sampled_requests_enabled   = var.enable_sampled_requests
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

#################################
# WAF Association with ALB
#################################

resource "aws_wafv2_web_acl_association" "groble_waf_alb_association" {
  resource_arn = var.load_balancer_arn
  web_acl_arn  = aws_wafv2_web_acl.groble_waf.arn
}

#################################
# CloudWatch Log Group for WAF
#################################

resource "aws_cloudwatch_log_group" "waf_log_group" {
  name              = "aws-waf-logs-${var.project_name}-waf"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-waf-logs"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

#################################
# WAF Logging Configuration
#################################

resource "aws_wafv2_web_acl_logging_configuration" "groble_waf_logging" {
  resource_arn            = aws_wafv2_web_acl.groble_waf.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_log_group.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}