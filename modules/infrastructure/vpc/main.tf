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
    name   = "state"
    values = ["available"]
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
# 프라이빗 서브넷 
#################################
resource "aws_subnet" "groble_vpc_private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.groble_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name    = "${var.project_name}_vpc_private_${count.index + 1}"
    Type    = "Private"
    Purpose = "Database and stateful services"
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

#################################
# 라우팅 테이블 - 프라이빗 (NAT 인스턴스 사용)
#################################
resource "aws_route_table" "groble_private_rt" {
  vpc_id = aws_vpc.groble_vpc.id

  # NAT instance route will be added dynamically via separate route resource
  tags = {
    Name = "${var.project_name}-private-route-table"
  }
}

# 프라이빗 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "groble_private_rta" {
  count = length(aws_subnet.groble_vpc_private)

  subnet_id      = aws_subnet.groble_vpc_private[count.index].id
  route_table_id = aws_route_table.groble_private_rt.id
}

#################################
# NAT Gateway (Phase 3)
#################################
# 모니터링 EC2 의 NAT 겸직을 대체한다. 생성만으로는 트래픽 경로가 바뀌지 않는다 —
# private route table 의 0.0.0.0/0 이 이쪽을 가리키게 되는 시점에 전환된다
# (그 라우트는 platform/ecs-cluster 모듈이 소유한다. 이유는 아래 주석 참조).

data "aws_region" "current" {}

# EIP 는 NAT Gateway 보다 먼저, 단독으로 만든다.
# 전환 후 외부에서 보이는 우리 출발지 IP 가 이 값이고, 외부 업체 허용목록에
# 등록해야 하는 것도 이 값이다. 등록에는 상대의 처리 시간이 걸리므로 IP 를 먼저
# 확보해 전달하고, NAT Gateway 는 등록이 끝난 뒤에 만든다.
# NAT Gateway 가 이 EIP 를 그대로 물기 때문에 등록한 IP 와 실제 나가는 IP 가 일치한다.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.create_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat.id
  subnet_id     = local.nat_gateway_subnet_id

  tags = {
    Name = "${var.project_name}-nat-gateway"
  }

  # IGW 가 없으면 NAT Gateway 는 만들어져도 인터넷에 닿지 못한다
  depends_on = [aws_internet_gateway.groble_internet_gateway]
}

# NAT Gateway 를 둘 서브넷은 인덱스가 아니라 AZ 로 고른다.
# 계획서 §2.2 가 "서브넷을 인덱스로 참조하면 우연에 의존한다"고 지적한 부분이며,
# 실제로 이 리소스는 AZ 를 잘못 고르면 전 구성요소 2c 정렬이 깨진다.
locals {
  nat_gateway_subnet_id = one([
    for idx, az in var.availability_zones : aws_subnet.groble_vpc_public[idx].id
    if az == var.nat_gateway_az
  ])
}

#################################
# S3 Gateway Endpoint (Phase 3)
#################################
# ECR 이미지 레이어는 S3 에서 내려온다. 이 엔드포인트가 없으면 그 트래픽이 전부
# NAT Gateway 의 데이터 처리 요금($0.059/GB)을 탄다. Gateway 형식이라 시간당 요금이 없다.
#
# private route table 에만 붙인다. public route table 쪽(모니터링 노드의 Loki S3 적재)은
# 이미 IGW 로 나가 NAT 요금이 붙지 않으므로 얻을 것이 없다.
#
# ⚠️ 생성과 라우트 테이블 연결을 분리해 두었다. 엔드포인트에 route_table_ids 를 직접
#    걸면 생성되는 순간 private route table 에 S3 prefix-list 라우트가 들어가고,
#    그 시점에 S3 로 가던 기존 연결(앱 파일 업로드 · ECR 레이어 pull)이 끊긴다.
#    "만들어만 두는" 단계가 무해하려면 연결은 별도 리소스여야 한다.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.groble_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.project_name}-s3-gateway-endpoint"
  }
}

# 이 리소스가 생기는 순간 S3 트래픽 경로가 바뀐다 (위 주석 참조).
resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  count = var.attach_s3_endpoint_to_private_rt ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = aws_route_table.groble_private_rt.id
}
