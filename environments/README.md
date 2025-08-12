# Groble Infrastructure - Environment Management

이 폴더는 Groble 인프라의 환경별 설정을 관리합니다.

## 📁 폴더 구조

```
environments/
├── shared/                  # 공유 환경 (인프라 기반 + 플랫폼)
│   ├── main.tf            # 공유 리소스 메인 설정
│   ├── terraform.tfvars   # 공유 환경 변수 값
│   ├── variables.tf       # 공유 환경 변수 정의
│   └── versions.tf        # Terraform & Provider 버전
├── dev/                    # 개발 환경 (서비스 계층)
│   ├── main.tf            # 개발 환경 메인 설정
│   ├── terraform.tfvars   # 개발 환경 변수 값
│   ├── variables.tf       # 개발 환경 변수 정의
│   └── versions.tf        # Terraform & Provider 버전
└── prod/                  # 프로덕션 환경 (서비스 계층)
    ├── main.tf            # 프로덕션 환경 메인 설정
    ├── terraform.tfvars   # 프로덕션 환경 변수 값
    ├── variables.tf       # 프로덕션 환경 변수 정의
    └── versions.tf        # Terraform & Provider 버전
```

## 🚀 사용 방법

> **중요**: 반드시 아래 순서대로 배포해야 합니다!

### 1단계: 공유 인프라 배포

```bash
# 공유 환경 폴더로 이동
cd environments/shared

# Terraform 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 2단계: 개발 환경 배포

```bash
# 개발 환경 폴더로 이동
cd environments/dev

# Terraform 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 3단계: 프로덕션 환경 배포

```bash
# 프로덕션 환경 폴더로 이동
cd environments/prod

# Terraform 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

## 🔧 환경별 차이점

### Shared Environment (shared/)
- **역할**: 개발/프로덕션 환경에서 공유하는 인프라 리소스
- **리소스**: VPC, 보안 그룹, ALB, ECS 클러스터, Route53, CodeDeploy
- **인스턴스**: 모든 환경용 EC2 인스턴스 생성 (프로덕션, 개발, 모니터링)
- **주의사항**: 이 환경이 먼저 생성되어야 다른 환경이 정상 작동

### Development Environment (dev/)
- **역할**: 개발 및 테스트용 서비스 배포
- **서비스**: Spring Boot API, MySQL, Redis (개발용 설정)
- **ECR**: 개발용 repository
- **로그**: 개발용 CloudWatch 로그 (3일 보관)
- **리소스 크기**: 비용 절약을 위해 작은 인스턴스 타입 사용
- **이미지 보관**: 최대 5개 이미지만 보관

### Production Environment (prod/)
- **역할**: 실제 운영용 서비스 배포
- **서비스**: Spring Boot API, MySQL, Redis (프로덕션용 설정)
- **ECR**: 프로덕션용 repository
- **로그**: 프로덕션용 CloudWatch 로그 (7일 보관)
- **리소스 크기**: 성능을 위해 더 큰 인스턴스 타입 사용
- **이미지 보관**: 최대 10개 이미지 보관
- **배포**: Blue/Green 배포 지원

## 📋 주요 변수 설정

### 공통 변수 (모든 환경)
- `project_name`: "groble"
- `vpc_cidr`: "10.0.0.0/16"
- `availability_zones`: ["ap-northeast-2a", "ap-northeast-2c"]

### 공유 환경 주요 변수 (shared/)
- `environment`: "shared"
- `enable_deletion_protection`: true/false (ALB 삭제 보호)
- `ssl_certificate_arn`: SSL 인증서 ARN
- `key_pair_name`: EC2 인스턴스용 키 페어
- `prod_instance_count`: 프로덕션 인스턴스 개수
- `prod_deployment_config`: 프로덕션 배포 설정
- `dev_deployment_config`: 개발 배포 설정

### 개발 환경 주요 변수 (dev/)
- `environment`: "dev"
- `mysql_database`: "groble_develop_database"
- `spring_profiles`: "dev,common,secret-dev,proxy"
- `server_env`: "development"

### 프로덕션 환경 주요 변수 (prod/)
- `environment`: "prod"
- `mysql_database`: "groble_prod_database"
- `spring_profiles`: "prod,common,secret-prod,proxy"
- `server_env`: "production"

## 🔐 보안 주의사항

1. **민감한 정보**: `terraform.tfvars` 파일에는 데이터베이스 패스워드 등 민감한 정보가 포함되어 있습니다.
2. **Git 관리**: 민감한 정보가 포함된 파일은 `.gitignore`에 추가하거나 별도로 관리하세요.
3. **접근 제어**: `trusted_ips` 변수를 통해 SSH 접근을 제한하세요.

## 📝 배포 전 체크리스트

### 공유 환경 (shared/) - 먼저 배포 필수!
- [ ] AWS 프로파일 설정 확인 (`groble-terraform`)
- [ ] SSL 인증서 ARN 확인 (메인 도메인 + 와일드카드)
- [ ] 키 페어 존재 확인 (EC2 인스턴스용)
- [ ] VPC CIDR 및 서브넷 계획 확인
- [ ] 로드 밸런서 삭제 보호 설정 결정
- [ ] CodeDeploy 배포 설정 확인

### 개발 환경 (dev/)
- [ ] 공유 환경이 먼저 배포되어 있는지 확인
- [ ] AWS 프로파일 설정 확인 (`groble-terraform`)
- [ ] 개발용 데이터베이스 패스워드 설정
- [ ] 개발용 환경 변수 확인
- [ ] ECR 레포지토리 이미지 준비

### 프로덕션 환경 (prod/)
- [ ] 공유 환경이 먼저 배포되어 있는지 확인
- [ ] AWS 프로파일 설정 확인 (`groble-terraform`)
- [ ] 프로덕션용 데이터베이스 패스워드 설정
- [ ] 프로덕션용 환경 변수 확인
- [ ] ECR 레포지토리 이미지 준비
- [ ] 백업 및 롤백 계획 수립
- [ ] Blue/Green 배포 설정 확인

## 🛠️ 트러블슈팅

### 일반적인 문제
1. **AWS 인증 오류**: AWS CLI 프로파일 설정을 확인하세요.
2. **키 페어 오류**: 지정된 키 페어가 해당 리전에 존재하는지 확인하세요.
3. **SSL 인증서 오류**: ACM에서 인증서가 발급되어 있는지 확인하세요.
4. **공유 리소스 의존성 오류**: 공유 환경이 먼저 배포되어 있는지 확인하세요.
5. **Output 값 참조 오류**: shared 환경의 output 값들이 올바르게 설정되어 있는지 확인하세요.

### 리소스 충돌
- 다른 환경과 리소스 이름이 충돌할 수 있습니다.
- `project_name` 변수를 조정하거나 리소스 이름을 수정하세요.
- 공유 환경 리소스는 모든 환경에서 공통으로 사용되므로 주의가 필요합니다.

### 배포 순서 관련 문제
- **Shared → Dev → Prod** 순서로 배포해야 합니다.
- 만약 순서를 잘못 배포했다면:
  1. 실패한 환경을 `terraform destroy`로 제거
  2. 올바른 순서로 다시 배포

### 공유 환경 변경 시 주의사항
- 공유 환경 변경은 모든 환경에 영향을 줍니다.
- 변경 전 개발/프로덕션 환경에 미치는 영향을 반드시 검토하세요.
- 가능하면 maintenance window 동안 변경하세요.
