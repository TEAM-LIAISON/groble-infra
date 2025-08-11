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
echo ECS_INSTANCE_ATTRIBUTES='{"environment":"monitoring","role":"monitor-server"}' >> /etc/ecs/ecs.config
echo ECS_ENABLE_EXECUTION_ROLE_LOG_DRIVER=true >> /etc/ecs/ecs.config
echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config

# ECS Agent 다운로드 및 실행
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

# Squid HTTP/HTTPS 프록시 설치 및 설정
apt install -y squid
systemctl enable squid

# Squid 설정 파일 백업 및 새 설정 생성
cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
cat > /etc/squid/squid.conf << 'SQUID_EOF'
# Squid 프록시 설정 - Groble API Server용

# 접근 제어 목록 (ACL) 정의
acl allowed_subnet src 10.0.0.0/16
acl SSL_ports port 443 465 587 993 995 25
acl Safe_ports port 80 443 25 587 465 993 995
acl CONNECT method CONNECT

# 보안 규칙 (포트 제한 적용)
http_access deny !Safe_ports

# SMTP 포트를 위한 CONNECT 허용
http_access allow CONNECT SSL_ports allowed_subnet
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

# 타임아웃 설정 (SMTP 연결용)
connect_timeout 60 seconds
read_timeout 60 seconds
SQUID_EOF

# Squid 서비스 시작
systemctl restart squid

# Dante SOCKS 프록시 서버 설치 및 설정
apt install -y dante-server

# Dante 설정 파일 생성
cat > /etc/danted.conf << 'DANTE_EOF'
# Dante SOCKS 프록시 설정

# 내부 인터페이스 (클라이언트 연결 수신)
internal: eth0 port = 1080

# 외부 인터페이스 (인터넷으로 나가는 연결)
external: eth0

# 인증 방법 (없음 - VPC 내부만 허용)
socksmethod: none

# 클라이언트 규칙
client pass {
    from: 10.0.0.0/16 to: 0.0.0.0/0
    log: connect disconnect error
}

# SOCKS 규칙
socks pass {
    from: 10.0.0.0/16 to: 0.0.0.0/0
    protocol: tcp udp
    command: bind connect udpassociate
    log: connect disconnect error
}

# 로그 설정
logoutput: /var/log/danted.log
DANTE_EOF

# Dante 서비스 설정 파일 생성
cat > /etc/systemd/system/danted.service << 'SERVICE_EOF'
[Unit]
Description=Dante SOCKS Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/danted -f /etc/danted.conf
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 서비스 활성화 및 시작
systemctl daemon-reload
systemctl enable danted
systemctl start danted

# 프록시 로그 디렉토리 권한 설정
chown -R proxy:proxy /var/log/squid
touch /var/log/danted.log
chmod 644 /var/log/danted.log

# 방화벽 규칙 추가 (SOCKS 포트)
iptables -A INPUT -p tcp --dport 1080 -s 10.0.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 3128 -s 10.0.0.0/16 -j ACCEPT

# iptables 규칙 저장
apt install -y iptables-persistent
netfilter-persistent save

# 테스트 스크립트 생성
cat > /home/ubuntu/test-proxy.sh << 'TEST_EOF'
#!/bin/bash
echo "=== Proxy Server Status ==="
echo ""
echo "1. Squid HTTP/HTTPS Proxy (Port 3128):"
systemctl status squid --no-pager | head -n 5
echo ""
echo "2. Dante SOCKS Proxy (Port 1080):"
systemctl status danted --no-pager | head -n 5
echo ""
echo "3. Listening Ports:"
netstat -tuln | grep -E ':(3128|1080)'
echo ""
echo "4. Test HTTP Proxy:"
curl -x http://localhost:3128 -I http://www.google.com 2>&1 | head -n 1
echo ""
echo "5. Test SOCKS Proxy:"
curl --socks5 localhost:1080 -I http://www.google.com 2>&1 | head -n 1
TEST_EOF
chmod +x /home/ubuntu/test-proxy.sh

# 모니터링 인스턴스 준비 완료 표시
echo "Monitoring instance ready for ECS" > /home/ubuntu/monitoring-ready.txt
echo "ECS Agent installed and configured" >> /home/ubuntu/monitoring-ready.txt
echo "Squid HTTP/HTTPS proxy server installed (Port 3128)" >> /home/ubuntu/monitoring-ready.txt
echo "Dante SOCKS5 proxy server installed (Port 1080)" >> /home/ubuntu/monitoring-ready.txt
echo "Proxy servers configured for VPC subnet 10.0.0.0/16" >> /home/ubuntu/monitoring-ready.txt
echo "Run /home/ubuntu/test-proxy.sh to test proxy servers" >> /home/ubuntu/monitoring-ready.txt
