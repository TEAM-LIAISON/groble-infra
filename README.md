# 🏗️ Groble Infrastructure

Groble 애플리케이션을 위한 AWS 인프라스트럭처 관리를 위한 Terraform 프로젝트입니다.

## 📁 프로젝트 구조

```
groble-infra/
├── README.md                    # 이 파일
├── .gitignore                   # Git 무시 파일
├── .terraform.lock.hcl         # Terraform 의존성 잠금
│
├── environments/               # 🌍 환경별 설정
│   ├── README.md              
│   ├── shared/                # 공유 환경 (인프라 기반 + 플랫폼)
│   │   ├── main.tf           # 공유 리소스 메인 설정
│   │   ├── terraform.tfvars  # 공유 환경 변수 값
│   │   ├── variables.tf      # 공유 환경 변수 정의
│   │   └── versions.tf       # Terraform & Provider 버전
│   ├── dev/                   # 개발 환경 (서비스 계층)
│   │   ├── main.tf           # 개발 환경 메인 설정
│   │   ├── terraform.tfvars  # 개발 환경 변수 값
│   │   ├── variables.tf      # 개발 환경 변수 정의
│   │   └── versions.tf       # Terraform & Provider 버전
│   └── prod/                  # 프로덕션 환경 (서비스 계층)
│       ├── main.tf           # 프로덕션 환경 메인 설정
│       ├── terraform.tfvars  # 프로덕션 환경 변수 값
│       ├── variables.tf      # 프로덕션 환경 변수 정의
│       └── versions.tf       # Terraform & Provider 버전
│
├── modules/                   # 📦 재사용 가능한 모듈들
│   ├── infrastructure/       # 🏗️ 인프라 기반 (변경 빈도: 낮음)
│   │   ├── vpc/             # VPC 및 네트워킹
│   │   ├── security-groups/ # 보안 그룹
│   │   ├── load-balancer/   # Application Load Balancer
│   │   ├── iam-roles/       # IAM 역할 및 정책
│   │   └── route53/         # DNS 및 도메인 관리
│   ├── platform/            # ⚙️ 플랫폼 계층 (변경 빈도: 중간)
│   │   ├── ecs-cluster/     # ECS 클러스터 관리
│   │   ├── ecr/             # 컨테이너 레지스트리
│   │   └── codedeploy/      # Blue/Green 배포
│   └── services/            # 🚀 서비스 계층 (변경 빈도: 높음)
│       ├── development/     # 개발 환경 서비스
│       │   ├── api-service/    # Spring Boot API
│       │   ├── mysql-service/  # MySQL 데이터베이스
│       │   └── redis-service/  # Redis 캐시
│       └── production/      # 프로덕션 환경 서비스
│           ├── api-service/    # Spring Boot API
│           ├── mysql-service/  # MySQL 데이터베이스
│           └── redis-service/  # Redis 캐시
│
├── shared/                    # 🔧 공통 설정
│   ├── README.md
│   ├── providers.tf          # Terraform 프로바이더 공통 설정
│   ├── variables.tf          # 공통 변수 정의
│   └── outputs.tf           # 공통 출력 정의
│
├── docs/                      # 📚 문서
│   └── README-deployment.md  # 배포 가이드
│
├── scripts/                   # 🔨 유틸리티 스크립트
│   └── deploy-step.sh        # 단계별 배포 스크립트
│
└── backups/                   # 💾 백업 파일들
    ├── *.tf.backup          # 기존 Terraform 파일들
    └── *.old                # 이전 설정 파일들
```

## 🏛️ 아키텍처 개요

### 3계층 아키텍처
1. **Infrastructure Layer** (인프라 기반) - `environments/shared`
   - VPC, 서브넷, 보안 그룹
   - Application Load Balancer
   - IAM 역할 및 정책
   - Route53 DNS

2. **Platform Layer** (플랫폼 계층) - `environments/shared`
   - ECS 클러스터 관리
   - ECR 컨테이너 레지스트리
   - CodeDeploy Blue/Green 배포

3. **Service Layer** (서비스 계층) - `environments/dev`, `environments/prod`
   - Spring Boot API 서비스
   - MySQL 데이터베이스 서비스
   - Redis 캐시 서비스

### 환경별 분리
- **Shared**: 공통 인프라 리소스 (VPC, ALB, ECS 클러스터, Route53 등)
- **Development**: 개발 및 테스트용 서비스
- **Production**: 실제 운영 서비스

## 🚀 빠른 시작

### 사전 요구사항
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) 설치 및 설정
- AWS 프로파일 `groble-terraform` 설정

### AWS 프로파일 설정
```bash
aws configure --profile groble-terraform
```

### 1단계: 공유 인프라 배포
```bash
# 공유 환경 폴더로 이동
cd environments/shared

# Terraform 초기화
terraform init

# 배포 계획 확인
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

# 배포 계획 확인
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

# 배포 계획 확인
terraform plan

# 배포 실행
terraform apply
```

> **중요**: 반드시 위 순서대로 배포해야 합니다. 공유 인프라가 먼저 생성되어야 개별 환경 서비스가 정상 작동합니다.

## 🌐 네트워크 구성

### VPC 설정
- **CIDR**: `10.0.0.0/16`
- **가용 영역**: `ap-northeast-2a`, `ap-northeast-2c`

### 서브넷 구성
- **퍼블릭 서브넷**: 
  - `10.0.1.0/24` (ap-northeast-2a)
  - `10.0.2.0/24` (ap-northeast-2c)
- **프라이빗 서브넷**:
  - `10.0.11.0/24` (ap-northeast-2a) 
  - `10.0.12.0/24` (ap-northeast-2c)

## 🔧 컴퓨팅 리소스

### ECS 클러스터
- **클러스터명**: `groble-cluster`
- **컨테이너 인사이트**: 활성화
- **CloudWatch 로깅**: 환경별 설정

### EC2 인스턴스
| 환경 | 인스턴스 타입 | 목적 | 개수 |
|------|---------------|------|------|
| Production | t3.small | 프로덕션 워크로드 | 1 |
| Development | t3.small | 개발 워크로드 | 1 |
| 공통 | t3.micro/small | 모니터링 | 1 |

## 🐳 컨테이너 서비스

### Spring Boot API
- **이미지**: ECR에서 관리
- **메모리**: 400-700MB (환경별)
- **CPU**: 256 units
- **포트**: 8080

### MySQL 8.0
- **메모리**: 256-500MB (환경별)
- **CPU**: 128-256 units (환경별)
- **포트**: 3306

### Redis 7
- **메모리**: 128MB
- **CPU**: 128 units
- **포트**: 6379

## ⚖️ 로드 밸런싱

### Application Load Balancer
- **유형**: 인터넷 연결
- **리스너**: HTTPS (443), HTTP (80 → 443 리다이렉트)
- **SSL 종료**: ALB에서 처리
- **Health Check**: `/actuator/health`

### 도메인 라우팅
- **Production**: `api.groble.im`
- **Development**: `api.dev.groble.im`
- **Monitoring**: `monitor.groble.im`

### Blue/Green 배포
- **Production**: 카나리 배포 지원
- **Development**: All-at-once 배포
- **자동 롤백**: 실패 시 자동 롤백

## 🔐 보안

### 보안 그룹
- **Load Balancer**: HTTP(80), HTTPS(443) 인바운드
- **API Tasks**: Load Balancer에서만 접근 허용
- **Database**: API Tasks에서만 접근 허용

### IAM 역할
- **ECS Task Execution Role**: ECR 풀, CloudWatch 로그 권한
- **ECS Task Role**: 애플리케이션별 AWS 서비스 접근 권한
- **CodeDeploy Service Role**: Blue/Green 배포 권한

### SSL/TLS
- **인증서**: AWS Certificate Manager (ACM)
- **암호화**: 전송 중 암호화 (HTTPS)
- **HTTP → HTTPS**: 자동 리다이렉트

## 📊 모니터링 및 로깅

### CloudWatch
- **Container Insights**: ECS 메트릭 수집
- **로그 그룹**: 환경별 분리
- **로그 보관**: 프로덕션 7일, 개발 3일

### 헬스 체크
- **경로**: `/actuator/health`
- **간격**: 30초
- **타임아웃**: 5초
- **임계값**: 연속 2회 실패 시 비정상

## 🚢 배포 파이프라인

### CodeDeploy
- **애플리케이션**: `groble-codedeploy-app`
- **배포 그룹**: 환경별 분리
- **배포 방식**: Blue/Green
- **트래픽 이동**: 환경별 설정

### ECR (Elastic Container Registry)
- **리포지토리**: 환경별 분리
- **이미지 스캔**: 활성화
- **Lifecycle**: 이미지 개수 제한 (Prod: 10개, Dev: 5개)

## 📝 주요 변수

### 공통 설정
```hcl
project_name = "groble"
aws_region = "ap-northeast-2"
vpc_cidr = "10.0.0.0/16"
```

### 환경별 차이점
| 설정 | Production | Development |
|------|------------|-------------|
| environment | "prod" | "dev" |
| mysql_database | "groble_prod_database" | "groble_develop_database" |
| spring_profiles | "prod,common,secret-prod,proxy" | "dev,common,secret-dev,proxy" |
| instance_type | t3.small | t3.small |
| mysql_memory | 500MB | 256MB |

## 🛠️ 유지보수

### 정기 작업
- [ ] ECR 이미지 정리 (Lifecycle Policy 자동)
- [ ] CloudWatch 로그 정리 (Retention Policy 자동)
- [ ] 보안 그룹 규칙 검토
- [ ] SSL 인증서 갱신 확인
- [ ] 공유 리소스 비용 모니터링 및 최적화

### 백업 및 복구
- [ ] Terraform 상태 파일 백업 (공유/개발/프로덕션 별도)
- [ ] 데이터베이스 스냅샷 (수동)
- [ ] 설정 파일 버전 관리
- [ ] 공유 인프라 복구 절차 문서화

## 🚨 트러블슈팅

### 자주 발생하는 문제
1. **AWS 인증 오류**
   - AWS 프로파일 설정 확인: `aws configure list --profile groble-terraform`

2. **키 페어 오류**
   - 키 페어 존재 확인: `aws ec2 describe-key-pairs --key-names groble_prod_ec2_key_pair`

3. **SSL 인증서 오류**
   - ACM에서 인증서 상태 확인

4. **포트 접근 문제**
   - 보안 그룹 규칙 확인
   - 타겟 그룹 헬스 체크 상태 확인

5. **공유 리소스 의존성 오류**
   - `environments/shared` 먼저 배포 여부 확인
   - 공유 리소스의 output 값들이 올바르게 설정되어 있는지 확인

### 로그 확인
```bash
# ECS 서비스 로그 확인
aws logs describe-log-groups --log-group-name-prefix "/ecs/groble"

# CloudWatch 메트릭 확인
aws cloudwatch list-metrics --namespace "AWS/ECS"
```

## 📞 지원

프로젝트 관련 문의사항이 있으시면 다음을 참고하세요:
- **문서**: `docs/` 폴더의 상세 가이드
- **스크립트**: `scripts/` 폴더의 자동화 도구
- **백업**: `backups/` 폴더의 이전 설정 파일

## 📈 향후 계획

- [ ] **원격 상태 관리**: S3 + DynamoDB 백엔드 설정 (공유/개발/프로덕션 환경별)
- [ ] **CI/CD 파이프라인**: GitHub Actions 통합
- [ ] **모니터링 강화**: Grafana 대시보드 추가
- [ ] **보안 강화**: AWS Config 규칙 적용
- [ ] **비용 최적화**: Spot 인스턴스 활용
- [ ] **멀티 리전**: 재해 복구 환경 구축
- [ ] **공유 리소스 최적화**: 환경별 카나리아 배포 및 로드 밸런싱 개선
