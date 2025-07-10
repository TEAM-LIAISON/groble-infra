#################################
# VPC 정보 (01-vpc.tf)
#################################
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.groble_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.groble_vpc.cidr_block
}

# 서브넷 정보 출력
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.groble_vpc_public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.groble_vpc_private[*].id
}

# 인터넷 게이트웨이 정보
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.groble_internet_gateway.id
}


# AMI 정보
output "ami_id" {
  description = "ID of the Ubuntu Noble AMI being used"
  value       = data.aws_ami.ubuntu_noble.id
}

output "ami_name" {
  description = "Name of the Ubuntu Noble AMI being used"
  value       = data.aws_ami.ubuntu_noble.name
}

#################################
# 보안 그룹 정보 (02-security-groups.tf)
#################################
output "security_group_ids" {
  description = "IDs of security groups"
  value = {
    load_balancer = try(aws_security_group.groble_load_balancer_sg.id, "Security group not yet created")
    production    = try(aws_security_group.groble_prod_target_group.id, "Security group not yet created")
    monitoring    = try(aws_security_group.groble_monitor_target_group.id, "Security group not yet created")
    development   = try(aws_security_group.groble_develop_target_group.id, "Security group not yet created")
    # bastion_host 제거됨 - Public Subnet 배치 전략으로 불필요
  }
}

#################################
# 로드밸런서 정보 (03-load-balancer.tf)
#################################
output "load_balancer_info" {
  description = "Load Balancer information"
  value = {
    arn      = try(aws_lb.groble_load_balancer.arn, "Load balancer not yet created")
    dns_name = try(aws_lb.groble_load_balancer.dns_name, "Load balancer not yet created")
    zone_id  = try(aws_lb.groble_load_balancer.zone_id, "Load balancer not yet created")
  }
}

# Blue/Green Target Group ARNs (ECS + CodeDeploy용)
output "target_group_arns" {
  description = "ARNs of all target groups for ECS and CodeDeploy"
  value = {
    prod_blue    = try(aws_lb_target_group.groble_prod_blue_tg.arn, "Target group not yet created")
    prod_green   = try(aws_lb_target_group.groble_prod_green_tg.arn, "Target group not yet created")
    dev_blue     = try(aws_lb_target_group.groble_dev_blue_tg.arn, "Target group not yet created")
    dev_green    = try(aws_lb_target_group.groble_dev_green_tg.arn, "Target group not yet created")
    monitoring   = try(aws_lb_target_group.groble_monitoring_tg.arn, "Target group not yet created")
  }
}

# Blue Target Group ARNs (초기 배포용)
output "blue_target_group_arns" {
  description = "ARNs of Blue target groups for initial deployment"
  value = {
    production  = try(aws_lb_target_group.groble_prod_blue_tg.arn, "Target group not yet created")
    development = try(aws_lb_target_group.groble_dev_blue_tg.arn, "Target group not yet created")
  }
}

#################################
# IAM 역할 정보 (04-iam-roles.tf)
#################################

# ECS 인스턴스 역할 정보
output "ecs_instance_role_info" {
  description = "ECS instance role information"
  value = {
    role_name    = try(aws_iam_role.ecs_instance_role.name, "IAM role not yet created")
    role_arn     = try(aws_iam_role.ecs_instance_role.arn, "IAM role not yet created")
    profile_name = try(aws_iam_instance_profile.ecs_instance_profile.name, "Instance profile not yet created")
    profile_arn  = try(aws_iam_instance_profile.ecs_instance_profile.arn, "Instance profile not yet created")
  }
}

# ECS 태스크 실행 역할 정보
output "ecs_task_execution_role_info" {
  description = "ECS task execution role information"
  value = {
    role_name = try(aws_iam_role.ecs_task_execution_role.name, "IAM role not yet created")
    role_arn  = try(aws_iam_role.ecs_task_execution_role.arn, "IAM role not yet created")
  }
}

# ECS 태스크 역할 정보
output "ecs_task_role_info" {
  description = "ECS task role information"
  value = {
    role_name = try(aws_iam_role.ecs_task_role.name, "IAM role not yet created")
    role_arn  = try(aws_iam_role.ecs_task_role.arn, "IAM role not yet created")
  }
}

# CodeDeploy 서비스 역할 정보
output "codedeploy_service_role_info" {
  description = "CodeDeploy service role information"
  value = {
    role_name = try(aws_iam_role.codedeploy_service_role.name, "IAM role not yet created")
    role_arn  = try(aws_iam_role.codedeploy_service_role.arn, "IAM role not yet created")
  }
}

# 모든 IAM 역할 ARN 요약
output "iam_role_arns_summary" {
  description = "Summary of all IAM role ARNs for ECS and CodeDeploy"
  value = {
    ecs_instance_role      = try(aws_iam_role.ecs_instance_role.arn, "Not created")
    ecs_task_execution_role = try(aws_iam_role.ecs_task_execution_role.arn, "Not created")
    ecs_task_role          = try(aws_iam_role.ecs_task_role.arn, "Not created")
    codedeploy_service_role = try(aws_iam_role.codedeploy_service_role.arn, "Not created")
    ecs_instance_profile   = try(aws_iam_instance_profile.ecs_instance_profile.arn, "Not created")
  }
}

#################################
# ECS 클러스터 정보 (05-ecs-cluster.tf)
#################################

# ECS 클러스터 정보
output "ecs_cluster_info" {
  description = "ECS cluster information"
  value = {
    cluster_name = try(aws_ecs_cluster.groble_cluster.name, "ECS cluster not yet created")
    cluster_arn  = try(aws_ecs_cluster.groble_cluster.arn, "ECS cluster not yet created")
    cluster_id   = try(aws_ecs_cluster.groble_cluster.id, "ECS cluster not yet created")
  }
}

# ECS 태스크 정의 정보
output "ecs_task_definitions" {
  description = "ECS task definition information"
  value = {
    production = {
      family   = try(aws_ecs_task_definition.groble_prod_task.family, "Task definition not yet created")
      arn      = try(aws_ecs_task_definition.groble_prod_task.arn, "Task definition not yet created")
      revision = try(aws_ecs_task_definition.groble_prod_task.revision, "Task definition not yet created")
    }
    development = {
      family   = try(aws_ecs_task_definition.groble_dev_task.family, "Task definition not yet created")
      arn      = try(aws_ecs_task_definition.groble_dev_task.arn, "Task definition not yet created")
      revision = try(aws_ecs_task_definition.groble_dev_task.revision, "Task definition not yet created")
    }
  }
}

#################################
# ECS 서비스 정보 (07-ecs-services.tf)
#################################

# ECS 서비스 정보
output "ecs_services" {
  description = "ECS service information (disabled until EC2 instances are deployed)"
  value = {
    prod_mysql = {
      name   = "${var.project_name}-prod-mysql-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_prod_mysql_service.id, "Service not yet created")
    }
    dev_mysql = {
      name   = "${var.project_name}-dev-mysql-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_dev_mysql_service.id, "Service not yet created")
    }
    prod_redis = {
      name   = "${var.project_name}-prod-redis-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_prod_redis_service.id, "Service not yet created")
    }
    dev_redis = {
      name   = "${var.project_name}-dev-redis-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_dev_redis_service.id, "Service not yet created")
    }
    prod_api = {
      name   = "${var.project_name}-prod-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_prod_service.id, "Service not yet created")
    }
    dev_api = {
      name   = "${var.project_name}-dev-service"
      status = "Disabled - waiting for EC2 instances"
      # service_arn = try(aws_ecs_service.groble_dev_service.id, "Service not yet created")
    }
  }
}

# CloudWatch 로그 그룹 정보 (현재 주석 처리됨)
output "cloudwatch_log_groups" {
  description = "CloudWatch log group information (disabled for cost savings)"
  value = {
    production = {
      name   = "/ecs/${var.project_name}-production"
      status = "Disabled - cost savings"
      # log_group_name = try(aws_cloudwatch_log_group.groble_prod_logs.name, "Log group not created")
    }
    development = {
      name   = "/ecs/${var.project_name}-development"
      status = "Disabled - cost savings"
      # log_group_name = try(aws_cloudwatch_log_group.groble_dev_logs.name, "Log group not created")
    }
  }
}

#################################
# CodeDeploy 정보 (08-codedeploy.tf - 현재 비활성화)
#################################

# CodeDeploy 애플리케이션 정보 (향후 배포 예정)
output "codedeploy_info" {
  description = "CodeDeploy application information (not yet deployed)"
  value = {
    application_name = "${var.project_name}-app"
    status          = "Not deployed yet"
    # application_id = try(aws_codedeploy_application.groble_app.id, "Application not created")
  }
}

#################################
# EC2 인스턴스 정보 (06-ec2-instances.tf - 현재 비활성화)
#################################

# EC2 인스턴스 정보 (향후 배포 예정)
output "ec2_instances" {
  description = "EC2 instance information (not yet deployed)"
  value = {
    production = {
      status = "Not deployed yet"
      # instance_id = try(aws_instance.groble_prod_instance[0].id, "Instance not created")
      # public_ip   = try(aws_instance.groble_prod_instance[0].public_ip, "Instance not created")
      # private_ip  = try(aws_instance.groble_prod_instance[0].private_ip, "Instance not created")
    }
    development = {
      status = "Not deployed yet"
      # instance_id = try(aws_instance.groble_develop_instance.id, "Instance not created")
      # public_ip   = try(aws_instance.groble_develop_instance.public_ip, "Instance not created")
      # private_ip  = try(aws_instance.groble_develop_instance.private_ip, "Instance not created")
    }
    monitoring = {
      status = "Not deployed yet"
      # instance_id = try(aws_instance.groble_monitoring_instance.id, "Instance not created")
      # public_ip   = try(aws_instance.groble_monitoring_instance.public_ip, "Instance not created")
      # private_ip  = try(aws_instance.groble_monitoring_instance.private_ip, "Instance not created")
    }
  }
}

#################################
# 배포 상태 요약
#################################

# 현재 배포 상태 요약
output "deployment_status" {
  description = "Current deployment status summary"
  value = {
    "01_vpc"           = "✅ Deployed"
    "02_security_groups" = "✅ Deployed"
    "03_load_balancer"  = "✅ Deployed"
    "04_iam_roles"      = "✅ Deployed"
    "05_ecs_cluster"    = "✅ Deployed (cluster + task definitions)"
    "06_ec2_instances"  = "⏳ Next to deploy"
    "07_ecs_services"   = "⏳ Waiting for EC2 instances"
    "08_codedeploy"     = "⏳ Waiting for ECS services"
    
    next_steps = [
      "1. Enable and deploy EC2 instances (06-ec2-instances.tf)",
      "2. Enable and deploy ECS services (07-ecs-services.tf)",
      "3. Enable and deploy CodeDeploy (08-codedeploy.tf)"
    ]
  }
}

# 주요 접속 정보
output "access_info" {
  description = "Key access information"
  value = {
    load_balancer_dns = try(aws_lb.groble_load_balancer.dns_name, "Load balancer not yet created")
    production_url    = "https://${try(aws_lb.groble_load_balancer.dns_name, "pending")}"
    development_url   = "https://dev.${try(aws_lb.groble_load_balancer.dns_name, "pending")}"
    monitoring_url    = "https://monitor.${try(aws_lb.groble_load_balancer.dns_name, "pending")}"
    
    note = "URLs will be functional after EC2 instances and ECS services are deployed"
  }
}
