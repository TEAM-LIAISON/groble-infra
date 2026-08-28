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
# CloudWatch 로그 그룹 (비활성화)
#################################

# Production 로그 그룹 (비활성화)
# resource "aws_cloudwatch_log_group" "prod_logs" {
#   count             = var.create_prod_logs ? 1 : 0
#   name              = "/ecs/${var.project_name}-production"
#   retention_in_days = var.prod_log_retention_days
#  
#   tags = {
#     Name        = "${var.project_name}-prod-logs"
#     Environment = "production"
#   }
# }

# Development 로그 그룹 (비활성화)
# resource "aws_cloudwatch_log_group" "dev_logs" {
#   count             = var.create_dev_logs ? 1 : 0
#   name              = "/ecs/${var.project_name}-development"
#   retention_in_days = var.dev_log_retention_days
# 
#   tags = {
#     Name        = "${var.project_name}-dev-logs"
#     Environment = "development"
#   }
# }

#################################
# 프로덕션 EC2 인스턴스
#################################

resource "aws_instance" "prod_instance" {
  count = var.create_prod_instance ? var.prod_instance_count : 0

  ami                         = var.ubuntu_ami_id
  instance_type               = var.prod_instance_type
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids      = [var.prod_security_group_id]
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  private_ip                  = var.prod_instance_private_ip
  iam_instance_profile        = var.ecs_instance_profile_name
  associate_public_ip_address = false

  # Root volume configuration
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-prod-root-volume-${count.index + 1}"
      Type = "Production"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/prod_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name        = "${var.project_name}-prod-instance-${count.index + 1}"
    Type        = "Production"
    Cluster     = "${var.project_name}-cluster"
    environment = "production"
  }
}

#################################
# 모니터링 EC2 인스턴스
#################################

resource "aws_instance" "monitoring_instance" {
  count = var.create_monitoring_instance ? 1 : 0

  ami                         = var.ubuntu_ami_id
  instance_type               = var.monitoring_instance_type
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids      = [var.monitoring_security_group_id]
  subnet_id                   = var.public_subnet_ids[0] # ap-northeast-2a 유지 (기존 subnet-019b5f63cabd29f4d)
  private_ip                  = var.monitoring_instance_private_ip
  iam_instance_profile        = var.ecs_instance_profile_name
  associate_public_ip_address = true
  source_dest_check           = false # Disable for NAT functionality

  # Root volume configuration with increased storage
  root_block_device {
    volume_size           = var.monitoring_root_volume_size
    volume_type           = var.monitoring_root_volume_type
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-monitoring-root-volume"
      Type = "Monitoring"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/monitoring_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  # user_data는 인스턴스 재생성을 유발하므로 무시 (credential 프록시 iptables 등
  # 스크립트 변경은 의도적 재생성 시에만 반영). ami와 동일한 이유로 고정.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name        = "${var.project_name}-monitoring-instance"
    Type        = "Monitoring"
    Cluster     = "${var.project_name}-cluster"
    environment = "monitoring"
  }
}

#################################
# 개발 EC2 인스턴스
#################################

resource "aws_instance" "dev_instance" {
  count = var.create_dev_instance ? 1 : 0

  ami                         = var.ubuntu_ami_id
  instance_type               = var.dev_instance_type
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null
  vpc_security_group_ids      = [var.dev_security_group_id]
  subnet_id                   = var.private_subnet_ids[1] # ap-northeast-2c private subnet
  private_ip                  = var.dev_instance_private_ip
  iam_instance_profile        = var.ecs_instance_profile_name
  associate_public_ip_address = false

  # Root volume configuration
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-dev-root-volume"
      Type = "Development"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/dev_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name        = "${var.project_name}-develop-instance"
    Type        = "Development"
    Cluster     = "${var.project_name}-cluster"
    environment = "development"
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

# private route table 의 기본 경로(0.0.0.0/0). 이 한 줄이 아웃바운드 전체를 결정한다.
#
# ⚠️ 리소스를 둘로 쪼개지 말 것 (NAT 인스턴스용 / NAT Gateway 용).
#    같은 route table 의 같은 목적지를 두 리소스가 다투게 되어, Terraform 이
#    destroy → create 로 처리하면 그 사이 기본 경로가 사라져 egress 가 통째로
#    블랙홀이 된다. 반대 순서면 RouteAlreadyExists 로 실패한다.
#    한 리소스에서 타깃 속성만 바꾸면 provider 가 ReplaceRoute 로 원자적으로
#    갈아끼우므로 경로가 비는 순간이 없다.
#
# 전환/롤백은 use_nat_gateway 값 하나로 한다. apply 전 plan 이
# "~ update in-place" 인지 반드시 육안 확인할 것 — "-/+ replace" 로 나오면
# 위의 블랙홀 구간이 생긴다는 뜻이므로 중단한다.
resource "aws_route" "private_nat_route" {
  count = var.create_monitoring_instance || var.use_nat_gateway ? 1 : 0

  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id       = var.use_nat_gateway ? var.nat_gateway_id : null
  network_interface_id = var.use_nat_gateway ? null : one(aws_instance.monitoring_instance[*].primary_network_interface_id)

  # NAT Gateway 가 아직 없는데 기본 경로를 그쪽으로 돌리면 egress 가 통째로 죽는다.
  # apply 가 시작되기 전에 막는다.
  lifecycle {
    precondition {
      condition     = !var.use_nat_gateway || var.nat_gateway_id != ""
      error_message = "use_nat_gateway = true 인데 nat_gateway_id 가 비어 있다. create_nat_gateway 를 먼저 true 로 두고 apply 할 것."
    }
  }

  depends_on = [aws_instance.monitoring_instance]
}
