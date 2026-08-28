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

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.groble_private_rt.id
}

output "ubuntu_ami_id" {
  description = "ID of the latest Ubuntu Noble AMI"
  value       = data.aws_ami.ubuntu_noble.id
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}

# NAT Gateway 관련 출력
output "nat_gateway_id" {
  description = "ID of the NAT Gateway. 아직 만들지 않았으면 null 이다"
  value       = one(aws_nat_gateway.main[*].id)
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway 의 고정 공인 IP. 외부 업체 허용목록에 등록해야 하는 값이다"
  value       = aws_eip.nat.public_ip
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}
