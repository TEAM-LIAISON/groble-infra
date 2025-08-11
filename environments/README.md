# Groble Infrastructure - Environment Management

이 폴더는 Groble 인프라의 환경별 설정을 관리합니다.

## 📁 폴더 구조

```
environments/
├── dev/                    # 개발 환경
│   ├── main.tf            # 개발 환경 메인 설정
│   ├── terraform.tfvars   # 개발 환경 변수 값
│   ├── variables.tf       # 개발 환경 변수 정의
│   └── versions.tf        # Terraform & Provider 버전
└── prod/                  # 프로덕션 환경
    ├── main.tf            # 프로덕션 환경 메인 설정
    ├── terraform.tfvars   # 프로덕션 환경 변수 값
    ├── variables.tf       # 프로덕션 환경 변수 정의
    └── versions.tf        # Terraform & Provider 버전
```

## 🚀 사용 방법

### 개발 환경 배포

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

### 프로덕션 환경 배포

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

### Development Environment (dev/)
- **인스턴스**: 개발용 + 모니터링용 인스턴스만 생성
- **ECR**: 개발용 repository만 생성
- **로그**: 개발용 CloudWatch 로그만 생성
- **서비스**: Development 서비스 모듈 사용
- **리소스 크기**: 비용 절약을 위해 작은 인스턴스 타입 사용
- **이미지 보관**: 최대 5개 이미지만 보관

### Production Environment (prod/)
- **인스턴스**: 프로덕션용 + 모니터링용 인스턴스만 생성
- **ECR**: 프로덕션용 repository만 생성
- **로그**: 프로덕션용 CloudWatch 로그만 생성
- **서비스**: Production 서비스 모듈 사용
- **리소스 크기**: 성능을 위해 더 큰 인스턴스 타입 사용
- **이미지 보관**: 최대 10개 이미지 보관

## 📋 주요 변수 설정

### 공통 변수
- `project_name`: "groble"
- `vpc_cidr`: "10.0.0.0/16"
- `availability_zones`: ["ap-northeast-2a", "ap-northeast-2c"]

### 개발 환경 주요 변수
- `environment`: "dev"
- `mysql_database`: "groble_develop_database"
- `spring_profiles`: "dev,common,secret-dev,proxy"
- `server_env`: "development"

### 프로덕션 환경 주요 변수
- `environment`: "prod"
- `mysql_database`: "groble_prod_database"
- `spring_profiles`: "prod,common,secret-prod,proxy"
- `server_env`: "production"

## 🔐 보안 주의사항

1. **민감한 정보**: `terraform.tfvars` 파일에는 데이터베이스 패스워드 등 민감한 정보가 포함되어 있습니다.
2. **Git 관리**: 민감한 정보가 포함된 파일은 `.gitignore`에 추가하거나 별도로 관리하세요.
3. **접근 제어**: `trusted_ips` 변수를 통해 SSH 접근을 제한하세요.

## 📝 배포 전 체크리스트

### 개발 환경
- [ ] AWS 프로파일 설정 확인 (`groble-terraform`)
- [ ] 개발용 데이터베이스 패스워드 설정
- [ ] SSL 인증서 ARN 확인
- [ ] 키 페어 존재 확인

### 프로덕션 환경
- [ ] AWS 프로파일 설정 확인 (`groble-terraform`)
- [ ] 프로덕션용 데이터베이스 패스워드 설정
- [ ] SSL 인증서 ARN 확인
- [ ] 키 페어 존재 확인
- [ ] 백업 및 롤백 계획 수립

## 🛠️ 트러블슈팅

### 일반적인 문제
1. **AWS 인증 오류**: AWS CLI 프로파일 설정을 확인하세요.
2. **키 페어 오류**: 지정된 키 페어가 해당 리전에 존재하는지 확인하세요.
3. **SSL 인증서 오류**: ACM에서 인증서가 발급되어 있는지 확인하세요.

### 리소스 충돌
- 다른 환경과 리소스 이름이 충돌할 수 있습니다.
- `project_name` 변수를 조정하거나 리소스 이름을 수정하세요.
