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

# 보안 그룹 정보 (2단계 이후에 생성됨)
output "security_group_ids" {
  description = "IDs of security groups"
  value = {
    load_balancer = try(aws_security_group.groble_load_balancer_sg.id, "Security group not yet created")
    production    = try(aws_security_group.groble_prod_target_group.id, "Security group not yet created")
    monitoring    = try(aws_security_group.groble_monitor_target_group.id, "Security group not yet created")
    development   = try(aws_security_group.groble_develop_target_group.id, "Security group not yet created")
    bastion_host  = try(aws_security_group.groble_bastion_sg.id, "Security group not yet created")
  }
}
