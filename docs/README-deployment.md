# Groble Infrastructure 단계적 배포 가이드

파일이 다음과 같이 분리되었습니다:

## 📁 파일 구조
```
01-vpc.tf                    # VPC, 서브넷, 라우팅 테이블
02-security-groups.tf        # 보안 그룹들
03-load-balancer.tf          # Application Load Balancer
04-iam-roles.tf              # IAM 역할들
05-ecs-cluster.tf            # ECS 클러스터, 태스크 정의
06-ec2-instances.tf.disabled # EC2 인스턴스들
07-ecs-services.tf.disabled  # ECS 서비스들
08-codedeploy.tf.disabled    # CodeDeploy
main.tf                      # 단계적 배포 가이드
deploy-step.sh               # 배포 헬퍼 스크립트
```

## 🚀 단계적 배포 방법

### 방법 1: 수동으로 파일 비활성화/활성화

1. **1단계 - VPC만 배포** (완료 ✅)
   ```bash
   # VPC 배포
   terraform plan
   terraform apply
   terraform show
   ```

2. **2단계 - 보안 그룹 추가** (완료 ✅)
   ```bash
   terraform plan
   terraform apply
   ```

3. **3단계 - 로드 밸런서 추가** (완료 ✅)
   ```bash
   terraform plan
   terraform apply
   ```

4. **4단계 - IAM 역할 추가** (완료 ✅)
   ```bash
   terraform plan
   terraform apply
   ```

5. **5단계 - ECS 클러스터 추가** (완료 ✅)
   ```bash
   terraform plan
   terraform apply
   ```

6. **6단계 - EC2 인스턴스 추가**
   ```bash
   mv 06-ec2-instances.tf.disabled 06-ec2-instances.tf
   terraform plan
   terraform apply
   ```

7. **7단계 - ECS 서비스 추가**
   ```bash
   mv 07-ecs-services.tf.disabled 07-ecs-services.tf
   terraform plan
   terraform apply
   ```

8. **8단계 - CodeDeploy 추가**
   ```bash
   mv 08-codedeploy.tf.disabled 08-codedeploy.tf
   terraform plan
   terraform apply
   ```

### 방법 2: 스크립트 사용 (추천)

```bash
# 스크립트 실행 권한 부여
chmod +x deploy-step.sh

# 1단계만 배포
./deploy-step.sh 1 plan
./deploy-step.sh 1 apply

# 2단계까지 배포
./deploy-step.sh 2 plan
./deploy-step.sh 2 apply

# 현재 상태 확인
./deploy-step.sh 2 show

# 특정 단계까지 삭제
./deploy-step.sh 1 destroy
```

## ⚠️ 주의사항

1. **AWS 자격증명 확인**: `groble-terraform` 프로필이 설정되어 있는지 확인
2. **키 페어**: EC2 인스턴스 배포 전에 `groble_prod_ec2_key_pair` 키 페어가 생성되어 있어야 함
3. **비용**: EC2 인스턴스와 로드 밸런서는 시간당 비용이 발생
4. **삭제 순서**: 삭제할 때는 역순으로 (4 → 3 → 2 → 1)

## 🔧 트러블슈팅

- 의존성 에러가 발생하면 이전 단계가 제대로 배포되었는지 확인
- 파일 확장자가 `.tf`인지 확인 (비활성화된 파일은 `.tf.disabled`)
- `terraform init`이 필요할 수 있음

## 📊 각 단계별 생성되는 리소스

**1단계 (01-vpc.tf):**
- VPC
- 인터넷 게이트웨이
- 퍼블릭/프라이빗 서브넷
- 라우팅 테이블

**2단계 (02-security-groups.tf):**
- 로드 밸런서 보안 그룹
- 프로덕션 서버 보안 그룹
- 모니터링 서버 보안 그룹
- 개발 서버 보안 그룹

**3단계 (03-load-balancer.tf):**
- Application Load Balancer
- 타겟 그룹 (Blue/Green)
- 리스너

**4단계 (04-iam-roles.tf):**
- ECS 인스턴스 역할
- ECS 태스크 실행 역할
- ECS 태스크 역할
- CodeDeploy 서비스 역할

**5단계 (05-ecs-cluster.tf):**
- ECS 클러스터
- 태스크 정의 (MySQL, Redis, Spring Boot)
- 서비스 디스커버리

**6단계 (06-ec2-instances.tf):**
- 프로덕션 인스턴스
- 개발 인스턴스
- 모니터링 인스턴스
- 타겟 그룹 연결

**7단계 (07-ecs-services.tf):**
- MySQL 서비스 (Prod/Dev)
- Redis 서비스 (Prod/Dev)
- Spring Boot API 서비스 (Prod/Dev)

**8단계 (08-codedeploy.tf):**
- CodeDeploy 애플리케이션
- 배포 그룹 (Prod/Dev)
- S3 버킷 (아티팩트 저장)
