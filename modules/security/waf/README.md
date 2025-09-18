# WAF 모듈

이 모듈은 Groble Application Load Balancer를 웹 공격으로부터 보호하기 위한 AWS WAF v2 Web ACL을 생성합니다.

## 기능

### AWS 관리형 규칙
- **핵심 규칙 세트**: 일반적인 웹 공격(OWASP Top 10)으로부터 보호
- **알려진 악성 입력**: 알려진 악성 요청 패턴 차단
- **SQL 인젝션 보호**: 고급 SQL 인젝션 공격 방어
- **IP 평판 목록**: 알려진 악성 IP 자동 차단

### 커스텀 규칙

#### 높은 우선순위 규칙
- **속도 제한**:
  - IP당: 5분에 2,000 요청
  - 전체: 5분에 50,000 요청
- **Spring Boot 보호**:
  - `/actuator/*` 엔드포인트 공개 접근 차단 (`/actuator/health` 제외)
- **요청 크기 제한**: 최대 1MB 요청 본문 크기

#### 중간 우선순위 규칙
- **지역 차단**: 아시아-태평양 지역으로 트래픽 제한 (설정 가능)
- **로그인 무차별 대입 공격 보호**: /login 엔드포인트에 대해 IP당 5분에 50 요청

### 모니터링 및 로깅
- 모든 규칙에 대한 CloudWatch 메트릭
- CloudWatch Logs로 상세 요청 로깅
- 분석을 위한 샘플 요청 데이터
- 민감 데이터 마스킹 (인증 헤더, 쿠키)

## 설정

### 기본 동작
모든 규칙은 초기에 **COUNT 모드**로 설정됩니다 - 잠재적인 공격을 로깅하지만 트래픽을 차단하지는 않습니다. 이를 통해 다음이 가능합니다:
1. 차단될 내용 모니터링
2. 정상적인 트래픽 패턴을 기반으로 규칙 조정
3. 확신이 설 때 BLOCK 모드로 전환

### 지원 국가 (지역 차단)
- KR (대한민국)
- JP (일본)
- SG (싱가포르)
- AU (호주)
- NZ (뉴질랜드)
- HK (홍콩)
- TW (대만)
- TH (태국)
- VN (베트남)
- MY (말레이시아)
- PH (필리핀)
- ID (인도네시아)
- IN (인도)

## 사용법

```hcl
module "waf" {
  source = "../../modules/security/waf"

  project_name       = "groble"
  environment        = "shared"
  load_balancer_arn  = module.load_balancer.load_balancer_arn

  # 속도 제한 (선택사항 - 기본값 표시)
  rate_limit_per_ip = 2000  # 5분당
  rate_limit_global = 50000 # 5분당

  # 모니터링 (선택사항 - 기본값 표시)
  enable_cloudwatch_metrics = true
  enable_sampled_requests   = true
  log_retention_days        = 30
}
```

## BLOCK 모드로 전환

COUNT 모드에서 모니터링한 후, `main.tf`에서 규칙 액션을 업데이트하여 규칙을 BLOCK 모드로 전환할 수 있습니다:

```hcl
# 변경 전:
action {
  count {}
}

# 변경 후:
action {
  block {}
}
```

## 모니터링

### CloudWatch 메트릭
- `CommonRuleSetMetric`: 핵심 웹 공격 패턴
- `KnownBadInputsMetric`: 악성 입력 패턴
- `SQLiRuleSetMetric`: SQL 인젝션 시도
- `IpReputationMetric`: 알려진 악성 IP 접근
- `RateLimitPerIPMetric`: IP별 속도 제한 위반 (높은 우선순위)
- `RateLimitGlobalMetric`: 전체 속도 제한 위반 (높은 우선순위)
- `ActuatorProtectionMetric`: Spring Boot actuator 접근 시도 (높은 우선순위)
- `RequestSizeLimitMetric`: 대용량 요청 본문 위반 (높은 우선순위)
- `GeoBlockingMetric`: 차단된 지역 (중간 우선순위)
- `LoginBruteForceMetric`: 로그인 무차별 대입 공격 보호 (중간 우선순위)

### CloudWatch 로그
WAF 로그는 다음 위치에 저장됩니다: `/aws/wafv2/{project_name}-waf`

로그 조회:
```bash
aws logs tail /aws/wafv2/groble-waf --follow
```

## 비용 추정

- Web ACL: 월 $1.00
- 규칙 (총 7개): 월 ~$7.00
- 요청: 백만 요청당 $0.60
- 로깅: CloudWatch Logs 표준 요금

**예상 월 비용**: 일반적인 스타트업 트래픽 기준 $10-15

## 보안 이점

- **DDoS 보호**: 속도 제한으로 자동화된 공격 방지
- **웹 공격 방어**: OWASP Top 10 보호
- **지역 보안**: 지역별 공격 표면 제한
- **SQL 인젝션 방어**: 데이터베이스 공격 방지
- **악성 IP 차단**: 자동 악성 행위자 방지
- **요청 분석**: 보안 모니터링을 위한 상세 로깅

## 다음 단계

1. COUNT 모드로 배포
2. 1-2주간 모니터링
3. 차단 vs 허용 트래픽 분석
4. 필요시 국가 코드 또는 속도 제한 조정
5. 적극적인 보호를 위해 BLOCK 모드로 전환