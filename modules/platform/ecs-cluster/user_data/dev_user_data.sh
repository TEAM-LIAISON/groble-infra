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
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
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

# 스왑 사용 정책 최적화 (메모리 부족시에만 사용)
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
