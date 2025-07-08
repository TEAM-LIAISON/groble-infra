# VPC 정보 출력
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

# 보안 그룹 정보
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

# 로드 밸런서 정보 (3단계 이후에 생성됨)
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
