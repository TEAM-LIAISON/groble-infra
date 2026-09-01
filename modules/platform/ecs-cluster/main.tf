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
    # 2026-08-30 Phase 4 — 이름을 역할에 맞췄다.
    # 관측 스택은 신 노드(groble-monitoring-v2-instance)로 옮겨가고, 이 노드에
    # 남는 것은 NAT·bastion·WireGuard 다. 실제 스택 이동은 E단계에서 한다.
    #
    # ⚠️ 태그 변경은 in-place 다(재생성 없음). egress 경로가 이 노드의 ENI 에
    #    걸려 있으므로 plan 에 replace 가 보이면 즉시 중단할 것.
    # ⚠️ Prometheus 가 이 태그를 instance_name 라벨로 승격한다. 변경 시점에
    #    해당 노드의 시계열이 끊긴다(규칙 의존 0건, 대시보드 연속성만 영향).
    Name    = "${var.project_name}-nat-instance"
    Type    = "Monitoring"
    Cluster = "${var.project_name}-cluster"

    # environment 는 그대로 둔다 — E단계 전까지 이 노드가 실제로 관측 스택을
    # 돌리고 있고, Prometheus 라벨과 ECS placement 판단에도 쓰인다.
    environment = "monitoring"
  }
}

#################################
# 신 모니터링 EC2 인스턴스 (Phase 4 — 모니터링 노드 재구축)
#################################
# 구 노드(public 2a, Ubuntu, NAT·bastion·VPN 겸직)를 대체하는 관측 전용 노드다.
# **구 노드를 대체하지만 없애지는 않는다** — NAT·bastion·VPN 은 구 노드에 남고,
# 그 폐기는 Phase 3(NAT) → Phase 10(접근 경로) → Phase 12(정리) 의 몫이다.
#
# 계획서 §0 에 따라 pet 으로 유지한다. ASG 로 만들지 않는다.

# AL2023 ECS-optimized AMI 는 AWS 가 SSM Parameter 로 최신값을 게시한다.
# ID 를 코드에 박으면 낡는다.
data "aws_ssm_parameter" "ecs_al2023_ami" {
  count = var.create_monitoring_v2_instance ? 1 : 0
  name  = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_instance" "monitoring_v2_instance" {
  count = var.create_monitoring_v2_instance ? 1 : 0

  ami           = data.aws_ssm_parameter.ecs_al2023_ami[0].value
  instance_type = var.monitoring_v2_instance_type

  # ⚠️ key_name 을 유지한다. 이 노드는 public IP 가 없어 진입 경로가
  #    SSM 과 WireGuard SSH 뿐이다. user_data 가 잘못되면 SSM 에이전트가
  #    등록되지 않을 수 있고, 그때 SSH 가 유일한 복구 수단이다.
  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  # private 2c. 구 노드는 public 2a 였다 — 계획서의 2c 정렬을 따른다.
  subnet_id                   = var.private_subnet_ids[1]
  private_ip                  = var.monitoring_v2_instance_private_ip
  associate_public_ip_address = false

  vpc_security_group_ids = [var.monitoring_security_group_id]
  iam_instance_profile   = var.ecs_instance_profile_name

  # source_dest_check 를 끄지 않는다 — 이 노드는 NAT 가 아니다.
  # 구 노드는 false 였다.

  root_block_device {
    volume_size           = var.monitoring_root_volume_size
    volume_type           = var.monitoring_root_volume_type
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-monitoring-v2-root-volume"
      Type = "Monitoring"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/monitoring_al2023_user_data.sh", {
    cluster_name = aws_ecs_cluster.cluster.name
  }))

  # ⚠️ ami 만 무시한다. user_data 는 일부러 무시하지 않는다.
  #
  #    구 노드는 `ignore_changes = [ami, user_data]` 였고, 그래서 **user_data 를
  #    고쳐도 실행 중 노드에 반영되지 않았다** — credential 프록시 iptables 버그를
  #    제자리에서 고칠 수 없었던 이유가 이것이다.
  #
  #    ami: SSM Parameter 가 AWS 의 AMI 릴리스마다 움직인다. 무시하지 않으면
  #         관계없는 apply 가 노드를 교체해 버린다. 교체는 의도적으로 한다
  #         (`terraform apply -replace=...` + 아래 순서).
  #    user_data: 바꾸면 plan 에 replace 로 **보인다**. 그것이 신호다 —
  #         모르는 사이 반영이 안 되는 것보다 낫다. 다만 이 노드는 pet 이므로
  #         replace 는 관측 단절을 뜻한다. 계획된 교체(E·F단계)로 처리할 것.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    # ⚠️ 구 노드와 다른 Name 이어야 한다. prod·dev 가 tag:Name 으로 인스턴스를
    #    조회하던 곳이 있었고(Phase 4 C단계에서 제거), 같은 이름이면 매치가
    #    2개가 되어 plan 이 깨진다.
    Name = "${var.project_name}-monitoring-v2-instance"
    Type = "Monitoring"

    # ⚠️ 이 태그가 없으면 Prometheus `ec2_sd_config` 가 이 노드를
    #    **경고 없이** 스크레이프 목록에서 누락한다
    #    (tag:Cluster = groble-cluster AND instance-state-name = running).
    Cluster = "${var.project_name}-cluster"

    environment = "monitoring"
    Phase       = "4"
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
# 모니터링 Target Group — **ECS 가 소유한다. Terraform 은 손대지 않는다**
#################################
# 2026-08-30 Phase 4 에서 정적 attachment 2개를 걷어냈다.
#
# Grafana ECS 서비스에 `load_balancer` 블록이 있어 **ECS 가 타깃 등록·해제를
# 직접 관리한다.** 태스크가 신 노드로 옮겨가자 ECS 가 구 노드를 자동으로 뺐고,
# 그 순간 Terraform 이 "다시 붙여야 한다"고 판단해 충돌이 드러났다.
#
# 정적 attachment 는 불필요했다. 스택이 어느 노드로 가든 ECS 가 따라간다 —
# 이 덕분에 Phase 4 F단계에서 "ALB 타깃그룹 재연결"이 수동 작업이 아니었다.
#
# `removed` 블록으로 state 에서만 분리한다. 실제 등록(ECS 가 만든 것)은 그대로 둔다 —
# destroy 하면 Grafana 가 ALB 에서 빠져 monitor.groble.im 이 죽는다.

removed {
  from = aws_lb_target_group_attachment.monitoring_attachment

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_lb_target_group_attachment.monitoring_v2_attachment

  lifecycle {
    destroy = false
  }
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
