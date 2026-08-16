# Terraform state 원격 저장소 (마이그레이션 Phase 0)
#
# 롤백: 이 파일을 삭제하고 백업해 둔 로컬 state를 복원한 뒤
#       terraform init -migrate-state
#
# - profile: backend는 provider 설정을 상속하지 않으므로 별도로 지정해야 한다
# - kms_key_id: 생략하면 backend가 SSE-S3(AES256) 헤더를 보내 버킷 기본
#   암호화(SSE-KMS)를 덮어쓴다. 감사 추적을 남기려면 명시해야 한다
# - use_lockfile: S3 네이티브 잠금 (Terraform 1.10+). DynamoDB 테이블 불필요

terraform {
  backend "s3" {
    bucket  = "groble-terraform-state"
    key     = "environments/prod/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "groble-terraform"

    encrypt      = true
    kms_key_id   = "arn:aws:kms:ap-northeast-2:538827147369:key/c555c131-6f6a-4422-80f3-e6ec79ff1e3a"
    use_lockfile = true
  }
}
