#################################
# 데이터 소스 - 최신 Amazon Linux AMI 조회
#################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
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

#################################
# 보안 그룹들
#################################

# 로드 밸런서용 보안 그룹
resource "aws_security_group" "groble_load_balancer_sg" {
  name        = "${var.project_name}-load-balancer-sg"
  description = "Security group for Groble Load Balancer"
  vpc_id      = aws_vpc.groble_vpc.id

  # HTTP 트래픽 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic"
  }

  # HTTPS 트래픽 허용
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic"
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-load-balancer-sg"
  }
}

# 프로덕션 타겟 그룹용 보안 그룹
resource "aws_security_group" "groble_prod_target_group" {
  name        = "${var.project_name}-prod-target-group"
  description = "Security group for Groble production instances"
  vpc_id      = aws_vpc.groble_vpc.id

  # 로드 밸런서로부터의 HTTP 트래픽
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "HTTP from load balancer"
  }

  # SSH 접근 (관리용)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH access from VPC"
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-prod-target-group"
  }
}

# 모니터링용 보안 그룹
resource "aws_security_group" "groble_monitor_target_group" {
  name        = "${var.project_name}-monitor-target-group"
  description = "Security group for Groble monitoring instance"
  vpc_id      = aws_vpc.groble_vpc.id

  # SSH 접근
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH access from VPC"
  }

  # 모니터링 대시보드 접근 (예: Grafana)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Monitoring dashboard access"
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-monitor-target-group"
  }
}

# 개발용 보안 그룹
resource "aws_security_group" "groble_develop_target_group" {
  name        = "${var.project_name}-develop-target-group"
  description = "Security group for Groble development instance"
  vpc_id      = aws_vpc.groble_vpc.id

  # SSH 접근
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH access from VPC"
  }

  # 개발 서버 접근 (다양한 포트)
  ingress {
    from_port   = 8000
    to_port     = 8999
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Development server access"
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-develop-target-group"
  }
}

#################################
# Application Load Balancer
#################################
resource "aws_lb" "groble_load_balancer" {
  name               = "${var.project_name}-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.groble_load_balancer_sg.id]
  subnets           = aws_subnet.groble_vpc_public[*].id

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = "${var.project_name}-load-balancer"
  }
}

# 타겟 그룹 - 프로덕션 인스턴스용
resource "aws_lb_target_group" "groble_prod_tg" {
  name     = "${var.project_name}-prod-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.groble_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-prod-tg"
  }
}

# 리스너 - HTTP 트래픽을 타겟 그룹으로 전달
resource "aws_lb_listener" "groble_listener" {
  load_balancer_arn = aws_lb.groble_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.groble_prod_tg.arn
  }
}

#################################
# EC2 인스턴스들
#################################

# 프로덕션 인스턴스 (2개, 각 AZ에 하나씩)
resource "aws_instance" "groble_prod_instance" {
  count = 2

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_prod_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_private[count.index].id

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Groble Production Server ${count.index + 1}</h1>" > /var/www/html/index.html
    echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
    echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
  EOF
  )

  tags = {
    Name = "${var.project_name}-prod-instance-${count.index + 1}"
    Type = "Production"
  }
}

# 모니터링 인스턴스
resource "aws_instance" "groble_monitoring_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_monitor_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_private[0].id

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    echo "Monitoring instance ready for setup" > /home/ec2-user/monitoring-ready.txt
  EOF
  )

  tags = {
    Name = "${var.project_name}-monitoring-instance"
    Type = "Monitoring"
  }
}

# 개발 인스턴스
resource "aws_instance" "groble_develop_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_develop_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_private[1].id

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git nodejs npm python3 pip3
    echo "Development instance ready" > /home/ec2-user/dev-ready.txt
  EOF
  )

  tags = {
    Name = "${var.project_name}-develop-instance"
    Type = "Development"
  }
}

# 타겟 그룹에 프로덕션 인스턴스들 연결
resource "aws_lb_target_group_attachment" "groble_prod_attachment" {
  count = length(aws_instance.groble_prod_instance)

  target_group_arn = aws_lb_target_group.groble_prod_tg.arn
  target_id        = aws_instance.groble_prod_instance[count.index].id
  port             = 80
}
