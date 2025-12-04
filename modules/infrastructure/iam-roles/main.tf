#################################
# ECS 관련 IAM 역할들
#################################

# ECS 인스턴스 역할 (EC2가 ECS 클러스터에 연결하기 위한 역할)
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-instance-role"
  }
}

# ECS 인스턴스 정책 연결 (EC2가 ECS와 통신할 수 있는 권한)
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# ECR 읽기 권한 추가 (Docker 이미지 pull)
resource "aws_iam_role_policy_attachment" "ecs_instance_ecr_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# CloudWatch 로그 권한 추가 (비활성화)
# resource "aws_iam_role_policy_attachment" "ecs_instance_cloudwatch_policy" {
#   role       = aws_iam_role.ecs_instance_role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
# }

# ECS 태스크 역할 가정 권한 (EC2 인스턴스가 ECS 태스크 역할을 가정할 수 있도록)
resource "aws_iam_role_policy" "ecs_instance_assume_task_role" {
  name = "${var.project_name}-ecs-instance-assume-task-role"
  role = aws_iam_role.ecs_instance_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/${var.project_name}-ecs-task-role"
      }
    ]
  })
}

# 인스턴스 프로파일 생성 (EC2 인스턴스에 IAM 역할 연결)
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name

  tags = {
    Name = "${var.project_name}-ecs-instance-profile"
  }
}

#################################
# ECS 태스크 실행 역할
#################################

# ECS 태스크 실행 역할 (Fargate/EC2에서 컨테이너 실행)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-execution-role"
  }
}

# ECS 태스크 실행 정책 연결
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR 전체 접근 권한 (이미지 push/pull)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_ecr_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

#################################
# ECS 태스크 역할 (애플리케이션에서 사용할 AWS 서비스 권한)
#################################

# ECS 태스크 역할 (컨테이너 애플리케이션이 AWS 서비스에 접근)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-role"
  }
}

# S3 접근 권한 (애플리케이션에서 S3 사용 시)
resource "aws_iam_role_policy_attachment" "ecs_task_s3_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# CloudWatch 로그 생성 권한 (비활성화)
# resource "aws_iam_role_policy_attachment" "ecs_task_cloudwatch_policy" {
#   role       = aws_iam_role.ecs_task_role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
# }

# KMS 암호화/복호화 권한 (애플리케이션에서 KMS 사용)
resource "aws_iam_role_policy_attachment" "ecs_task_kms_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
}

# KMS 키 사용 권한 (특정 키에 대한 명시적 권한)
resource "aws_iam_role_policy" "ecs_task_kms_key_usage" {
  name = "${var.project_name}-ecs-task-kms-key-usage"
  role = aws_iam_role.ecs_task_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:RetireGrant"
        ]
        Resource = "arn:aws:kms:ap-northeast-2:538827147369:key/*"
      }
    ]
  })
}

#################################
# CodeDeploy 서비스 역할
#################################

# CodeDeploy 서비스 역할
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.project_name}-codedeploy-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codedeploy-service-role"
  }
}

# CodeDeploy ECS 정책 연결
resource "aws_iam_role_policy_attachment" "codedeploy_service_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# CodeDeploy에서 ELB 조작 권한
resource "aws_iam_role_policy_attachment" "codedeploy_elb_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

#################################
# CodeDeploy 추가 정책 (ECS Blue/Green 배포용)
#################################

# CodeDeploy가 ECS 서비스와 태스크를 관리할 수 있는 추가 권한
resource "aws_iam_role_policy" "codedeploy_ecs_policy" {
  name = "${var.project_name}-codedeploy-ecs-policy"
  role = aws_iam_role.codedeploy_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:CreateTaskSet",
          "ecs:DeleteTaskSet",
          "ecs:DescribeServices",
          "ecs:UpdateServicePrimaryTaskSet",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "lambda:InvokeFunction",
          # "cloudwatch:DescribeAlarms",
          "sns:Publish",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "*"
      }
    ]
  })
}

#################################
# ECR 접근 권한 정책
#################################
resource "aws_iam_role_policy" "ecs_task_execution_ecr_policy" {
  name = "${var.project_name}-ecs-task-execution-ecr-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}
