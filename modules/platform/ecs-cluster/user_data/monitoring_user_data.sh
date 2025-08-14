#!/bin/bash
# 기본 패키지 업데이트
apt update -y
apt install -y curl wget unzip awscli jq

# Enable IP forwarding for NAT functionality
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 1 > /proc/sys/net/ipv4/ip_forward

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

# Configure NAT functionality for private subnet internet access
# NAT traffic from private subnets to internet
iptables -t nat -A POSTROUTING -s 10.0.11.0/24 -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.0.12.0/24 -o eth0 -j MASQUERADE

# Forward traffic between private subnets and internet
iptables -A FORWARD -s 10.0.11.0/24 -j ACCEPT
iptables -A FORWARD -s 10.0.12.0/24 -j ACCEPT
iptables -A FORWARD -d 10.0.11.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 10.0.12.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow SSH access from private subnets (for bastion functionality)
iptables -A INPUT -p tcp --dport 22 -s 10.0.11.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 10.0.12.0/24 -j ACCEPT

# Save iptables rules persistently
apt install -y iptables-persistent
netfilter-persistent save

# Create NAT testing script
cat > /home/ubuntu/test-nat.sh << 'TEST_EOF'
#!/bin/bash
echo "=== NAT Instance Status ==="
echo ""
echo "1. IP Forwarding Status:"
cat /proc/sys/net/ipv4/ip_forward
echo ""
echo "2. NAT Rules:"
iptables -t nat -L POSTROUTING -n -v
echo ""
echo "3. Forward Rules:"
iptables -L FORWARD -n -v
echo ""
echo "4. Network Interfaces:"
ip addr show eth0
echo ""
echo "5. Route Table:"
ip route
TEST_EOF
chmod +x /home/ubuntu/test-nat.sh

# 모니터링 및 NAT 인스턴스 준비 완료 표시
echo "Monitoring and NAT instance ready for ECS" > /home/ubuntu/monitoring-ready.txt
echo "ECS Agent installed and configured" >> /home/ubuntu/monitoring-ready.txt
echo "NAT functionality configured for private subnets:" >> /home/ubuntu/monitoring-ready.txt
echo "  - 10.0.11.0/24 (ap-northeast-2a private)" >> /home/ubuntu/monitoring-ready.txt
echo "  - 10.0.12.0/24 (ap-northeast-2c private)" >> /home/ubuntu/monitoring-ready.txt
echo "IP forwarding enabled" >> /home/ubuntu/monitoring-ready.txt
echo "iptables NAT and FORWARD rules configured" >> /home/ubuntu/monitoring-ready.txt
echo "Bastion host functionality available via SSH" >> /home/ubuntu/monitoring-ready.txt
echo "Run /home/ubuntu/test-nat.sh to test NAT functionality" >> /home/ubuntu/monitoring-ready.txt
