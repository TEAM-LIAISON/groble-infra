# VPC 관련 출력
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.groble_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.groble_vpc.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.groble_internet_gateway.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.groble_vpc_public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.groble_vpc_private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.groble_public_rt.id
}

output "ubuntu_ami_id" {
  description = "ID of the latest Ubuntu Noble AMI"
  value       = data.aws_ami.ubuntu_noble.id
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}
