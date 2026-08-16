# 부트스트랩 정책 문서

**이 디렉터리의 JSON은 Terraform이 관리하지 않는다.** 마이그레이션 Phase 0에서 AWS CLI로
직접 적용한 정책의 원본이며, "state를 담을 버킷의 state를 어디에 둘 것인가"라는 순환을
피하기 위해 의도적으로 Terraform 밖에 둔 것이다.

`terraform destroy`로 지워지지 않고, `terraform plan`에도 나타나지 않는다.
**변경이 필요하면 이 파일을 고치고 아래 명령으로 다시 적용한 뒤 커밋한다.**

| 파일 | 적용 대상 |
|---|---|
| `kms-key-policy.json` | KMS 키 `alias/groble/terraform-state` |
| `state-bucket-policy.json` | S3 `groble-terraform-state` |
| `state-bucket-lifecycle.json` | S3 `groble-terraform-state` |
| `cloudtrail-bucket-policy.json` | S3 `groble-cloudtrail-logs-538827147369` |
| `cloudtrail-lifecycle.json` | S3 `groble-cloudtrail-logs-538827147369` |
| `cloudtrail-event-selectors.json` | 트레일 `groble-audit` |

## 재적용

```bash
aws s3api put-bucket-policy --profile groble-terraform \
  --bucket groble-terraform-state --policy file://state-bucket-policy.json

aws kms put-key-policy --profile groble-terraform \
  --key-id alias/groble/terraform-state --policy-name default \
  --policy file://kms-key-policy.json

aws cloudtrail put-event-selectors --profile groble-terraform \
  --trail-name groble-audit --advanced-event-selectors file://cloudtrail-event-selectors.json
```

## 주의

`state-bucket-policy.json`과 `kms-key-policy.json`의 `aws:PrincipalArn` 목록을 좁힐 때는
**락아웃에 주의한다.** 이 계정에는 SSO 역할이 `AWSReservedSSO_TerraformPowerUser_*` 하나뿐이라,
역할 이름을 정확한 ARN으로 박으면 SSO 권한 세트 재프로비저닝 시 접미사가 바뀌어 접근이 끊긴다.
와일드카드와 탈출구를 유지하는 이유는 [`docs/runbook/phase-00-terraform-state-s3.md`](../docs/runbook/phase-00-terraform-state-s3.md)
0-c에 적어 두었다.
