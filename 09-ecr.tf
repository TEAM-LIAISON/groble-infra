#################################
# ECR (Elastic Container Registry)
#################################

#################################
# ECR 리포지토리 - Production Spring API
#################################
resource "aws_ecr_repository" "groble_prod_spring_api" {
  name                 = "${var.project_name}-prod-spring-api"
  image_tag_mutability = "MUTABLE"

  # 이미지 스캔 설정
  image_scanning_configuration {
    scan_on_push = true
  }

  # 암호화 설정
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-prod-spring-api"
    Environment = "production"
    Type        = "application"
  }
}

#################################
# ECR 리포지토리 - Development Spring API
#################################
resource "aws_ecr_repository" "groble_dev_spring_api" {
  name                 = "${var.project_name}-dev-spring-api"
  image_tag_mutability = "MUTABLE"

  # 이미지 스캔 설정
  image_scanning_configuration {
    scan_on_push = true
  }

  # 암호화 설정
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-dev-spring-api"
    Environment = "development"
    Type        = "application"
  }
}

#################################
# ECR 라이프사이클 정책 - Production
#################################
resource "aws_ecr_lifecycle_policy" "groble_prod_spring_api_policy" {
  repository = aws_ecr_repository.groble_prod_spring_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#################################
# ECR 라이프사이클 정책 - Development
#################################
resource "aws_ecr_lifecycle_policy" "groble_dev_spring_api_policy" {
  repository = aws_ecr_repository.groble_dev_spring_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "dev", "feature", "main"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#################################
# ECR 리포지토리 정책 - GitHub Actions 푸시 권한
#################################
resource "aws_ecr_repository_policy" "groble_prod_spring_api_policy" {
  repository = aws_ecr_repository.groble_prod_spring_api.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.ecs_task_execution_role.arn,
            aws_iam_role.ecs_task_role.arn
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "groble_dev_spring_api_policy" {
  repository = aws_ecr_repository.groble_dev_spring_api.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.ecs_task_execution_role.arn,
            aws_iam_role.ecs_task_role.arn
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}