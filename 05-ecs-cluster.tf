#################################
# ECS 클러스터
#################################

# ECS 클러스터 생성
resource "aws_ecs_cluster" "groble_cluster" {
  name = "${var.project_name}-cluster"
  
  # Container Insights
    setting {
      name  = "containerInsights"
      value = "enabled"  # CloudWatch Container Insights 활성화
    }
  
  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

#################################
# CloudWatch 로그 그룹
#################################

# Production 로그 그룹
resource "aws_cloudwatch_log_group" "groble_prod_logs" {
  name              = "/ecs/${var.project_name}-production"
  retention_in_days = 7
 
   tags = {
     Name        = "${var.project_name}-prod-logs"
     Environment = "production"
   }
}

# Development 로그 그룹
resource "aws_cloudwatch_log_group" "groble_dev_logs" {
  name              = "/ecs/${var.project_name}-development"
  retention_in_days = 3

  tags = {
    Name        = "${var.project_name}-dev-logs"
    Environment = "development"
  }
}

#################################
# 프로덕션 EC2 인스턴스
#################################

resource "aws_instance" "groble_prod_instance" {
  count = 1

  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = "t3.small"
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_prod_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_public[0].id
  iam_instance_profile  = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
#!/bin/bash
# 기본 패키지 업데이트
apt update -y
apt install -y curl wget unzip awscli jq

# Docker 설치 및 설정
apt install -y docker.io
systemctl start docker
systemctl enable docker
usermod -a -G docker ubuntu

# ECS Agent 설치 및 설정
mkdir -p /etc/ecs
echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES='{"environment":"production","role":"prod-server"}' >> /etc/ecs/ecs.config
echo ECS_ENABLE_EXECUTION_ROLE_LOG_DRIVER=true >> /etc/ecs/ecs.config
echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_ENI=true >> /etc/ecs/ecs.config
echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config
echo ECS_RESERVED_MEMORY=64 >> /etc/ecs/ecs.config
echo ECS_CONTAINER_STOP_TIMEOUT=30s >> /etc/ecs/ecs.config

# awsvpc 모드 지원을 위한 추가 시스템 설정
sysctl -w net.ipv4.conf.all.route_localnet=1
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679

# ECS Agent 다운로드 및 실행 (systemd 지원 포함)
mkdir -p /var/log/ecs /var/lib/ecs/data
docker run --name ecs-agent \
  --init \
  --detach=true \
  --restart=on-failure:10 \
  --volume=/run/systemd:/run/systemd \
  --volume=/var/run:/var/run \
  --volume=/var/log/ecs/:/log \
  --volume=/var/lib/ecs/data:/data \
  --volume=/etc/ecs:/etc/ecs \
  --volume=/proc:/host/proc \
  --volume=/sys/fs/cgroup:/sys/fs/cgroup \
  --volume=/var/lib/ecs/dhclient:/var/lib/ecs/dhclient \
  --volume=/sbin:/host/sbin \
  --volume=/lib:/lib \
  --volume=/lib64:/lib64 \
  --volume=/usr/lib:/usr/lib \
  --volume=/usr/lib64:/usr/lib64 \
  --net=host \
  --env-file=/etc/ecs/ecs.config \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_ADMIN \
  --env ECS_ENABLE_TASK_ENI=true \
  amazon/amazon-ecs-agent:latest

# Swap 파일 설정 (배포 시 메모리 부족 방지)
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 스왑 사용 정책 최적화 (메모리 부족시에만 사용)
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
sysctl -p

# 데이터 디렉토리 생성 (MySQL 볼륨용)
mkdir -p /opt/mysql-prod-data
chown -R 999:999 /opt/mysql-prod-data

# ECS 서비스 상태 확인용 스크립트 생성
cat > /home/ubuntu/check-ecs-services.sh << 'EOL'
#!/bin/bash
echo "Checking ECS services on this instance..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "Checking ECS agent capabilities:"
curl -s http://localhost:51678/v1/metadata | jq .
EOL
chmod +x /home/ubuntu/check-ecs-services.sh

# 인스턴스 준비 완료 표시
echo "Production instance ready for ECS with awsvpc support" > /home/ubuntu/instance-ready.txt
echo "ECS Agent installed and configured with ENI support" >> /home/ubuntu/instance-ready.txt
echo "Swap configured: 1GB with swappiness=10" >> /home/ubuntu/instance-ready.txt
echo "Data directories created" >> /home/ubuntu/instance-ready.txt
EOF
  )

  tags = {
    Name = "${var.project_name}-prod-instance-${count.index + 1}"
    Type = "Production"
  }
}

#################################
# 모니터링 EC2 인스턴스
#################################

resource "aws_instance" "groble_monitoring_instance" {
  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_monitor_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_public[0].id
  iam_instance_profile  = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
#!/bin/bash
# 기본 패키지 업데이트
apt update -y
apt install -y curl wget unzip awscli jq

# Docker 설치 및 설정
apt install -y docker.io
systemctl start docker
systemctl enable docker
usermod -a -G docker ubuntu

# ECS Agent 설치 및 설정
mkdir -p /etc/ecs
echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES='{"environment":"monitoring","role":"monitor-server"}' >> /etc/ecs/ecs.config
echo ECS_ENABLE_EXECUTION_ROLE_LOG_DRIVER=true >> /etc/ecs/ecs.config
echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config


# ECS Agent 다운로드 및 실행 (systemd 지원 포함)
mkdir -p /var/log/ecs /var/lib/ecs/data
docker run --name ecs-agent \
  --init \
  --detach=true \
  --restart=on-failure:10 \
  --volume=/run/systemd:/run/systemd \
  --volume=/var/run:/var/run \
  --volume=/var/log/ecs/:/log \
  --volume=/var/lib/ecs/data:/data \
  --volume=/etc/ecs:/etc/ecs \
  --volume=/proc:/host/proc \
  --volume=/sys/fs/cgroup:/sys/fs/cgroup \
  --volume=/var/lib/ecs/dhclient:/var/lib/ecs/dhclient \
  --volume=/sbin:/host/sbin \
  --volume=/lib:/lib \
  --volume=/lib64:/lib64 \
  --volume=/usr/lib:/usr/lib \
  --volume=/usr/lib64:/usr/lib64 \
  --net=host \
  --env-file=/etc/ecs/ecs.config \
  --cap-add=SYS_ADMIN \
  amazon/amazon-ecs-agent:latest

# Squid 프록시 서버 설치 및 설정
apt install -y squid
systemctl enable squid

# Squid 설정 파일 백업 및 새 설정 생성
cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
cat > /etc/squid/squid.conf << 'SQUID_EOF'
# Squid 프록시 설정 - Groble API Server용

# 접근 제어 목록 (ACL) 정의
acl allowed_subnet src 10.0.0.0/16
acl SSL_ports port 443 465 587 993 995
acl Safe_ports port 80 443 25 587 465 993 995
acl CONNECT method CONNECT

# 보안 규칙 (포트 제한 적용)
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# HTTP 접근 허용 (VPC 내부만)
http_access allow allowed_subnet
http_access deny all

# 포트 설정
http_port 3128

# 로깅 설정
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

# 캐시 비활성화 (프록시 전용)
cache deny all

# 포워딩된 IP 헤더 추가
forwarded_for on

# DNS 설정
dns_nameservers 169.254.169.253 8.8.8.8

# 에러 페이지 커스터마이징 (선택사항)
error_directory /usr/share/squid/errors/English
SQUID_EOF

# Squid 서비스 시작
systemctl start squid
systemctl restart squid

# 프록시 로그 디렉토리 권한 설정
chown -R proxy:proxy /var/log/squid

# 모니터링 인스턴스 준비 완료 표시
echo "Monitoring instance ready for ECS" > /home/ubuntu/monitoring-ready.txt
echo "ECS Agent installed and configured" >> /home/ubuntu/monitoring-ready.txt
echo "Squid proxy server installed and configured" >> /home/ubuntu/monitoring-ready.txt
echo "Proxy listening on port 3128 for VPC subnet 10.0.0.0/16" >> /home/ubuntu/monitoring-ready.txt
echo "Docker ready for monitoring tools (Grafana, Prometheus, etc.)" >> /home/ubuntu/monitoring-ready.txt
EOF
  )

  tags = {
    Name = "${var.project_name}-monitoring-instance"
    Type = "Monitoring"
  }
}

#################################
# 개발 EC2 인스턴스
#################################

resource "aws_instance" "groble_develop_instance" {
  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = "t3.small"
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_develop_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_public[1].id
  iam_instance_profile  = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
#!/bin/bash
# 기본 패키지 업데이트
apt update -y
apt install -y curl wget unzip awscli jq

# Docker 설치 및 설정
apt install -y docker.io
systemctl start docker
systemctl enable docker
usermod -a -G docker ubuntu

# ECS Agent 설치 및 설정
mkdir -p /etc/ecs
echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES='{"environment":"development","role":"dev-server"}' >> /etc/ecs/ecs.config
echo ECS_ENABLE_EXECUTION_ROLE_LOG_DRIVER=true >> /etc/ecs/ecs.config
echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_ENI=true >> /etc/ecs/ecs.config
echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config

# awsvpc 모드 지원을 위한 추가 시스템 설정
sysctl -w net.ipv4.conf.all.route_localnet=1
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679

# ECS Agent 다운로드 및 실행 (systemd 지원 포함)
mkdir -p /var/log/ecs /var/lib/ecs/data
docker run --name ecs-agent \
  --init \
  --detach=true \
  --restart=on-failure:10 \
  --volume=/run/systemd:/run/systemd \
  --volume=/var/run:/var/run \
  --volume=/var/log/ecs/:/log \
  --volume=/var/lib/ecs/data:/data \
  --volume=/etc/ecs:/etc/ecs \
  --volume=/proc:/host/proc \
  --volume=/sys/fs/cgroup:/sys/fs/cgroup \
  --volume=/var/lib/ecs/dhclient:/var/lib/ecs/dhclient \
  --volume=/sbin:/host/sbin \
  --volume=/lib:/lib \
  --volume=/lib64:/lib64 \
  --volume=/usr/lib:/usr/lib \
  --volume=/usr/lib64:/usr/lib64 \
  --net=host \
  --env-file=/etc/ecs/ecs.config \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_ADMIN \
  --env ECS_ENABLE_TASK_ENI=true \
  amazon/amazon-ecs-agent:latest

# 데이터 디렉토리 생성 (MySQL 볼륨용)
mkdir -p /opt/mysql-dev-data
chown -R 999:999 /opt/mysql-dev-data

# Swap 파일 설정 (t2.micro 메모리 부족 대비)
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 스욍 사용 정책 최적화 (메모리 부족시에만 사용)
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
sysctl -p

# ECS 서비스 상태 확인용 스크립트 생성
cat > /home/ubuntu/check-ecs-services.sh << 'EOL'
#!/bin/bash
echo "Checking ECS services on this instance..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
EOL
chmod +x /home/ubuntu/check-ecs-services.sh

# 개발 인스턴스 준비 완료 표시
echo "Development instance ready for ECS" > /home/ubuntu/dev-ready.txt
echo "ECS Agent installed and configured with memory optimization" >> /home/ubuntu/dev-ready.txt
echo "Swap configured: 1GB with swappiness=10" >> /home/ubuntu/dev-ready.txt
echo "Development tools removed - maintaining parity with production" >> /home/ubuntu/dev-ready.txt
echo "Data directories created" >> /home/ubuntu/dev-ready.txt
echo "Apache web server removed - using ECS containers only" >> /home/ubuntu/dev-ready.txt
EOF
  )

  tags = {
    Name = "${var.project_name}-develop-instance"
    Type = "Development"
  }
}


# 모니터링 인스턴스 연결
resource "aws_lb_target_group_attachment" "groble_monitoring_attachment" {
  target_group_arn = aws_lb_target_group.groble_monitoring_tg.arn
  target_id        = aws_instance.groble_monitoring_instance.id
  port             = 3000
}
