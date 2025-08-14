#################################
# ECS 클러스터
#################################

# ECS 클러스터 생성
resource "aws_ecs_cluster" "cluster" {
  name = "${var.project_name}-cluster"
  
  # Container Insights
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
  
  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

#################################
# CloudWatch 로그 그룹
#################################

# Production 로그 그룹
resource "aws_cloudwatch_log_group" "prod_logs" {
  count             = var.create_prod_logs ? 1 : 0
  name              = "/ecs/${var.project_name}-production"
  retention_in_days = var.prod_log_retention_days
 
  tags = {
    Name        = "${var.project_name}-prod-logs"
    Environment = "production"
  }
}

# Development 로그 그룹
resource "aws_cloudwatch_log_group" "dev_logs" {
  count             = var.create_dev_logs ? 1 : 0
  name              = "/ecs/${var.project_name}-development"
  retention_in_days = var.dev_log_retention_days

  tags = {
    Name        = "${var.project_name}-dev-logs"
    Environment = "development"
  }
}

#################################
# 프로덕션 EC2 인스턴스
#################################

resource "aws_instance" "prod_instance" {
  count = var.create_prod_instance ? var.prod_instance_count : 0

  ami                    = var.ubuntu_ami_id
  instance_type          = var.prod_instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [var.prod_security_group_id]
  subnet_id             = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  iam_instance_profile  = var.ecs_instance_profile_name
  associate_public_ip_address = false

  user_data = base64encode(templatefile("${path.module}/user_data/prod_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  tags = {
    Name = "${var.project_name}-prod-instance-${count.index + 1}"
    Type = "Production"
  }
}

#################################
# 모니터링 EC2 인스턴스
#################################

resource "aws_instance" "monitoring_instance" {
  count = var.create_monitoring_instance ? 1 : 0

  ami                    = var.ubuntu_ami_id
  instance_type          = var.monitoring_instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [var.monitoring_security_group_id]
  subnet_id             = var.public_subnet_ids[0]  # ap-northeast-2a 유지 (기존 subnet-019b5f63cabd29f4d)
  iam_instance_profile  = var.ecs_instance_profile_name
  associate_public_ip_address = true
  source_dest_check     = false  # Disable for NAT functionality

  user_data = base64encode(templatefile("${path.module}/user_data/monitoring_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  tags = {
    Name = "${var.project_name}-monitoring-instance"
    Type = "Monitoring"
  }
}

#################################
# 개발 EC2 인스턴스
#################################

resource "aws_instance" "dev_instance" {
  count = var.create_dev_instance ? 1 : 0

  ami                    = var.ubuntu_ami_id
  instance_type          = var.dev_instance_type
  key_name              = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids = [var.dev_security_group_id]
  subnet_id             = var.private_subnet_ids[1]  # ap-northeast-2c private subnet
  iam_instance_profile  = var.ecs_instance_profile_name
  associate_public_ip_address = false

  user_data = base64encode(templatefile("${path.module}/user_data/dev_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  tags = {
    Name = "${var.project_name}-develop-instance"
    Type = "Development"
  }
}

#################################
# 모니터링 인스턴스 Target Group 연결
#################################

resource "aws_lb_target_group_attachment" "monitoring_attachment" {
  count            = var.create_monitoring_instance ? 1 : 0
  target_group_arn = var.monitoring_target_group_arn
  target_id        = aws_instance.monitoring_instance[0].id
  port             = 3000
}

#################################
# NAT 인스턴스 라우트 설정
#################################

# Private route table에 NAT instance route 추가
resource "aws_route" "private_nat_route" {
  count                  = var.create_monitoring_instance ? 1 : 0
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.monitoring_instance[0].primary_network_interface_id
  
  depends_on = [aws_instance.monitoring_instance]
}
