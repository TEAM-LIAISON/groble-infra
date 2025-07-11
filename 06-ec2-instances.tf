#################################
# EC2 인스턴스들
#################################

# 프로덕션 인스턴스 (1개)
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
    apt install -y curl wget unzip awscli
    
    # Docker 설치 및 설정
    apt install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ubuntu
    
    # ECS Agent 설치 및 설정
    mkdir -p /etc/ecs
    echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
    echo ECS_INSTANCE_ATTRIBUTES='{"environment":"production","role":"prod-server"}' >> /etc/ecs/ecs.config
    echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
    echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
    echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
    echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config
    
    # ECS Agent 다운로드 및 실행
    mkdir -p /var/log/ecs /var/lib/ecs/data
    docker run --name ecs-agent \
      --detach=true \
      --restart=on-failure:10 \
      --volume=/var/run:/var/run \
      --volume=/var/log/ecs/:/log \
      --volume=/var/lib/ecs/data:/data \
      --volume=/etc/ecs:/etc/ecs \
      --net=host \
      --env-file=/etc/ecs/ecs.config \
      amazon/amazon-ecs-agent:latest
    
    # Apache 설치 (기본 웹서버)
    apt install -y apache2
    systemctl start apache2
    systemctl enable apache2
    
    # 기본 웹페이지 설정
    echo "<h1>Groble Production Server ${count.index + 1}</h1>" > /var/www/html/index.html
    echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
    echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
    echo "<p>OS: Ubuntu Noble 24.04 LTS</p>" >> /var/www/html/index.html
    echo "<p>ECS Cluster: ${aws_ecs_cluster.groble_cluster.name}</p>" >> /var/www/html/index.html
    
    # 인스턴스 준비 완료 표시
    echo "Production instance ready for ECS" > /home/ubuntu/instance-ready.txt
    echo "ECS Agent installed and configured" >> /home/ubuntu/instance-ready.txt
  EOF
  )

  tags = {
    Name = "${var.project_name}-prod-instance-${count.index + 1}"
    Type = "Production"
  }
}

# 모니터링 인스턴스
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
    apt install -y curl wget unzip awscli
    
    # Docker 설치 및 설정
    apt install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ubuntu
    
    # ECS Agent 설치 및 설정
    mkdir -p /etc/ecs
    echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
    echo ECS_INSTANCE_ATTRIBUTES='{"environment":"monitoring","role":"monitor-server"}' >> /etc/ecs/ecs.config
    echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
    echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
    echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
    echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config
    
    # ECS Agent 다운로드 및 실행
    mkdir -p /var/log/ecs /var/lib/ecs/data
    docker run --name ecs-agent \
      --detach=true \
      --restart=on-failure:10 \
      --volume=/var/run:/var/run \
      --volume=/var/log/ecs/:/log \
      --volume=/var/lib/ecs/data:/data \
      --volume=/etc/ecs:/etc/ecs \
      --net=host \
      --env-file=/etc/ecs/ecs.config \
      amazon/amazon-ecs-agent:latest
    
    # 모니터링 인스턴스 준비 완료 표시
    echo "Monitoring instance ready for ECS" > /home/ubuntu/monitoring-ready.txt
    echo "ECS Agent installed and configured" >> /home/ubuntu/monitoring-ready.txt
    echo "Docker ready for monitoring tools (Grafana, Prometheus, etc.)" >> /home/ubuntu/monitoring-ready.txt
  EOF
  )

  tags = {
    Name = "${var.project_name}-monitoring-instance"
    Type = "Monitoring"
  }
}

# 개발 인스턴스
resource "aws_instance" "groble_develop_instance" {
  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [aws_security_group.groble_develop_target_group.id]
  subnet_id             = aws_subnet.groble_vpc_public[1].id
  iam_instance_profile  = aws_iam_instance_profile.ecs_instance_profile.name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # 기본 패키지 업데이트
    apt update -y
    apt install -y curl wget unzip awscli git
    
    # Docker 설치 및 설정
    apt install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ubuntu
    
    # ECS Agent 설치 및 설정
    mkdir -p /etc/ecs
    echo ECS_CLUSTER=${aws_ecs_cluster.groble_cluster.name} >> /etc/ecs/ecs.config
    echo ECS_INSTANCE_ATTRIBUTES='{"environment":"development","role":"dev-server"}' >> /etc/ecs/ecs.config
    echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true >> /etc/ecs/ecs.config
    echo ECS_LOGFILE=/log/ecs-agent.log >> /etc/ecs/ecs.config
    echo ECS_AVAILABLE_LOGGING_DRIVERS='["json-file","awslogs"]' >> /etc/ecs/ecs.config
    echo ECS_LOGLEVEL=info >> /etc/ecs/ecs.config
    
    # ECS Agent 다운로드 및 실행
    mkdir -p /var/log/ecs /var/lib/ecs/data
    docker run --name ecs-agent \
      --detach=true \
      --restart=on-failure:10 \
      --volume=/var/run:/var/run \
      --volume=/var/log/ecs/:/log \
      --volume=/var/lib/ecs/data:/data \
      --volume=/etc/ecs:/etc/ecs \
      --net=host \
      --env-file=/etc/ecs/ecs.config \
      amazon/amazon-ecs-agent:latest
    
    # 개발 도구 설치
    apt install -y nodejs npm python3 python3-pip apache2
    systemctl start apache2
    systemctl enable apache2
    
    # Node.js 최신 LTS 설치
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs
    
    # 기본 웹페이지 설정
    echo "<h1>Groble Development Server</h1>" > /var/www/html/index.html
    echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
    echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
    echo "<p>OS: Ubuntu Noble 24.04 LTS</p>" >> /var/www/html/index.html
    echo "<p>Environment: Development</p>" >> /var/www/html/index.html
    echo "<p>ECS Cluster: ${aws_ecs_cluster.groble_cluster.name}</p>" >> /var/www/html/index.html
    
    # 개발 인스턴스 준비 완료 표시
    echo "Development instance ready for ECS" > /home/ubuntu/dev-ready.txt
    echo "ECS Agent installed and configured" >> /home/ubuntu/dev-ready.txt
    echo "Development tools: Node.js, Python, Git installed" >> /home/ubuntu/dev-ready.txt
  EOF
  )

  tags = {
    Name = "${var.project_name}-develop-instance"
    Type = "Development"
  }
}

# 타겟 그룹에 프로덕션 인스턴스들 연결 (Blue 타겟 그룹)
resource "aws_lb_target_group_attachment" "groble_prod_attachment" {
  count = length(aws_instance.groble_prod_instance)

  target_group_arn = aws_lb_target_group.groble_prod_blue_tg.arn
  target_id        = aws_instance.groble_prod_instance[count.index].id
  port             = 80
}

# 모니터링 인스턴스 연결
resource "aws_lb_target_group_attachment" "groble_monitoring_attachment" {
  target_group_arn = aws_lb_target_group.groble_monitoring_tg.arn
  target_id        = aws_instance.groble_monitoring_instance.id
  port             = 3000
}

# 개발 인스턴스 연결 (Blue 타겟 그룹)
resource "aws_lb_target_group_attachment" "groble_dev_attachment" {
  target_group_arn = aws_lb_target_group.groble_dev_blue_tg.arn
  target_id        = aws_instance.groble_develop_instance.id
  port             = 80
}


