#################################
# ECR (Elastic Container Registry)
#################################

#################################
# ECR 리포지토리 - Production Spring API
#################################
resource "aws_ecr_repository" "prod_spring_api" {
  count                = var.create_prod_repository ? 1 : 0
  name                 = "${var.project_name}-prod-spring-api"
  image_tag_mutability = var.image_tag_mutability

  # 이미지 스캔 설정
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  # 암호화 설정
  encryption_configuration {
    encryption_type = var.encryption_type
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
resource "aws_ecr_repository" "dev_spring_api" {
  count                = var.create_dev_repository ? 1 : 0
  name                 = "${var.project_name}-dev-spring-api"
  image_tag_mutability = var.image_tag_mutability

  # 이미지 스캔 설정
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  # 암호화 설정
  encryption_configuration {
    encryption_type = var.encryption_type
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
resource "aws_ecr_lifecycle_policy" "prod_spring_api_policy" {
  count      = var.create_prod_repository ? 1 : 0
  repository = aws_ecr_repository.prod_spring_api[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.prod_max_image_count} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.prod_tag_prefixes
          countType     = "imageCountMoreThan"
          countNumber   = var.prod_max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_expiry_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
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
resource "aws_ecr_lifecycle_policy" "dev_spring_api_policy" {
  count      = var.create_dev_repository ? 1 : 0
  repository = aws_ecr_repository.dev_spring_api[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.dev_max_image_count} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.dev_tag_prefixes
          countType     = "imageCountMoreThan"
          countNumber   = var.dev_max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_expiry_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#################################
# ECR 리포지토리 정책 - Production
#################################
resource "aws_ecr_repository_policy" "prod_spring_api_policy" {
  count      = var.create_prod_repository ? 1 : 0
  repository = aws_ecr_repository.prod_spring_api[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principals
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

#################################
# ECR 리포지토리 정책 - Development
#################################
resource "aws_ecr_repository_policy" "dev_spring_api_policy" {
  count      = var.create_dev_repository ? 1 : 0
  repository = aws_ecr_repository.dev_spring_api[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principals
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
