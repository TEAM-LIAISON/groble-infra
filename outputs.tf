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
