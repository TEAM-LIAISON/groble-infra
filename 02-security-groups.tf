#################################
# 로드 밸런서용 보안 그룹
#################################
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

#################################
# 프로덕션용 보안 그룹
#################################
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


#################################
# 모니터링용 보안 그룹
#################################
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

  # 로드밸런서에서 3000번 포트 접근 허용
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "Monitoring dashboard from load balancer"
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


#################################
# 개발용 보안 그룹
#################################
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

  # 로드밸런서에서 80번 포트 접근 허용 (개발 서버용)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "HTTP from load balancer for development"
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
# Bastion Host 보안 그룹
#################################
resource "aws_security_group" "groble_bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for Bastion Host"
  vpc_id      = aws_vpc.groble_vpc.id

  # SSH 접근 (특정 IP만)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_ips
    description = "SSH access from trusted IPs"
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
    Name = "${var.project_name}-bastion-sg"
  }
}

#################################
# Bastion Host에서 각 인스턴스로의 SSH 접근 규칙
#################################

# Prod 보안 그룹에 Bastion SSH 접근 허용
resource "aws_security_group_rule" "prod_ssh_from_bastion" {
  type                     = "ingress"
  from_port               = 22
  to_port                 = 22
  protocol                = "tcp"
  security_group_id       = aws_security_group.groble_prod_target_group.id
  source_security_group_id = aws_security_group.groble_bastion_sg.id
  description             = "SSH access from Bastion Host"
}

# Monitoring 보안 그룹에 Bastion SSH 접근 허용
resource "aws_security_group_rule" "monitoring_ssh_from_bastion" {
  type                     = "ingress"
  from_port               = 22
  to_port                 = 22
  protocol                = "tcp"
  security_group_id       = aws_security_group.groble_monitor_target_group.id
  source_security_group_id = aws_security_group.groble_bastion_sg.id
  description             = "SSH access from Bastion Host"
}

# Development 보안 그룹에 Bastion SSH 접근 허용
resource "aws_security_group_rule" "dev_ssh_from_bastion" {
  type                     = "ingress"
  from_port               = 22
  to_port                 = 22
  protocol                = "tcp"
  security_group_id       = aws_security_group.groble_develop_target_group.id
  source_security_group_id = aws_security_group.groble_bastion_sg.id
  description             = "SSH access from Bastion Host"
}
