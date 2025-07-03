#################################
# 데이터 소스 - 최신 Ubuntu Noble 24.04 LTS AMI 조회
#################################
data "aws_ami" "ubuntu_noble" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu 공식 계정)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

#################################
# VPC - 가상 사설 클라우드
#################################
resource "aws_vpc" "groble_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

#################################
# 인터넷 게이트웨이 - 외부 인터넷 연결
#################################
resource "aws_internet_gateway" "groble_internet_gateway" {
  vpc_id = aws_vpc.groble_vpc.id

  tags = {
    Name = "${var.project_name}-internet-gateway"
  }
}

#################################
# 퍼블릭 서브넷 - 로드 밸런서용
#################################
resource "aws_subnet" "groble_vpc_public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.groble_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}_vpc_public_${count.index + 1}"
    Type = "Public"
  }
}

#################################
# 프라이빗 서브넷 - EC2 인스턴스용
#################################
resource "aws_subnet" "groble_vpc_private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.groble_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}_vpc_private_${count.index + 1}"
    Type = "Private"
  }
}

#################################
# 라우팅 테이블 - 퍼블릭
#################################
resource "aws_route_table" "groble_public_rt" {
  vpc_id = aws_vpc.groble_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.groble_internet_gateway.id
  }

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

# 퍼블릭 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "groble_public_rta" {
  count = length(aws_subnet.groble_vpc_public)

  subnet_id      = aws_subnet.groble_vpc_public[count.index].id
  route_table_id = aws_route_table.groble_public_rt.id
}
