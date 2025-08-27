#################################
# 로드 밸런서용 보안 그룹
#################################
resource "aws_security_group" "groble_load_balancer_sg" {
  name        = "${var.project_name}-load-balancer-sg"
  description = "Security group for Groble Load Balancer"
  vpc_id      = var.vpc_id

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

  # CodeDeploy 테스트용 HTTPS 포트 허용 (ex. 9443)
  ingress {
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic for CodeDeploy test listener"
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
  vpc_id      = var.vpc_id

  # 로드 밸런서로부터의 HTTP 트래픽
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "HTTP from load balancer"
  }

  # ECS 동적 포트 매핑을 위한 포트 범위
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "Dynamic port mapping for ECS"
  }

  # SSH 접근 (관리용) - Public Subnet 배치를 위해 특정 IP에서만 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_ips
    description = "SSH access from trusted IPs"
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MySQL access from VPC"
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Redis access from VPC"
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
  vpc_id      = var.vpc_id
  
  # SSH 접근 - Public Subnet 배치를 위해 특정 IP에서만 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_ips
    description = "SSH access from trusted IPs"
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
  
  # NAT instance - Allow all traffic from private subnets
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.11.0/24", "10.0.12.0/24"]
    description = "NAT traffic from private subnets (TCP)"
  }
  
  # NAT instance - Allow all UDP traffic from private subnets
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.0.11.0/24", "10.0.12.0/24"]
    description = "NAT traffic from private subnets (UDP)"
  }

  # NAT instance - Allow ICMP from private subnets
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.11.0/24", "10.0.12.0/24"]
    description = "ICMP from private subnets"
  }

  # SSH access from private subnets (bastion host functionality)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.11.0/24", "10.0.12.0/24"]
    description = "SSH access from private subnets"
  }
  
  # OpenTelemetry Collector OTLP gRPC
  ingress {
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "OTLP gRPC receiver for telemetry"
  }
  
  # OpenTelemetry Collector OTLP HTTP
  ingress {
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "OTLP HTTP receiver for telemetry"
  }
  
  # OpenTelemetry Collector Health Check
  ingress {
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Health check endpoint for OpenTelemetry Collector"
  }
  
  # OpenTelemetry Collector Prometheus Metrics (Internal)
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus metrics endpoint for OpenTelemetry Collector (internal)"
  }
  
  # OpenTelemetry Collector Exported Metrics (from Applications)
  ingress {
    from_port   = 8889
    to_port     = 8889
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus metrics endpoint for application metrics (exported)"
  }
  
  # Loki HTTP API
  ingress {
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Loki HTTP API for log ingestion and queries"
  }
  
  # Prometheus HTTP API
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus HTTP API for metrics queries"
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
  vpc_id      = var.vpc_id

  # SSH 접근 - Public Subnet 배치를 위해 특정 IP에서만 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_ips
    description = "SSH access from trusted IPs"
  }

  # MySQL 접근 - Service Discovery Health Check 및 컨테이너 간 통신
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MySQL access from VPC"
  }

  # Redis 접근 - Service Discovery Health Check 및 컨테이너 간 통신
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Redis access from VPC"
  }

  # 로드밸런서에서 80번 포트 접근 허용 (개발 서버용)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "HTTP from load balancer for development"
  }

  # ECS 동적 포트 매핑을 위한 포트 범위
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "Dynamic port mapping for ECS"
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
# API Server 태스크용 보안 그룹 (awsvpc 모드)
#################################
resource "aws_security_group" "groble_api_task_sg" {
  name        = "${var.project_name}-api-task-sg"
  description = "Security group for Groble API Server tasks (awsvpc mode)"
  vpc_id      = var.vpc_id

  # 로드밸런서에서 8080 포트 접근 허용
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.groble_load_balancer_sg.id]
    description     = "HTTP from load balancer to API Server"
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
    Name = "${var.project_name}-api-task-sg"
    Type = "task-security-group"
  }
}
