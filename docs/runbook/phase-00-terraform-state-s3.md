# Phase 0 — Terraform state를 S3로 이전

> [← 이관 절차 목차](README.md) · [다음: Phase 1 →](./phase-01-alarm-backstop.md)

| | |
|---|---|
| **상태** | ✅ 완료 (2026-08-16) |
| **목적** | 이후 모든 단계가 state를 크게 조작한다. 잠금·이력·백업 없이 진행하지 않는다 |
| **사용자 영향** | 없음 (실물 인프라 무변경) |
| **되돌리기** | 로컬 state 복원 |

---

## ✅ 완료 요약

> **이 문서는 이미 끝난 작업의 기록이다.** 아래 절차는 다시 따라 할 것이 아니라, 지금 배포된 상태가
> 어떻게 만들어졌는지와 되돌리는 방법을 남겨둔 것이다.

- **배포된 것** — 환경 4곳(`shared`·`prod`·`dev`·`monitoring`)의 state가 S3 `groble-terraform-state`로 이전됐다.
  환경별 `backend.tf` 별도 파일 · S3 네이티브 잠금(`use_lockfile`) · SSE-KMS(`alias/groble/terraform-state`) · versioning.
  Terraform은 1.5.7 → **1.15.8**(`.terraform-version` 고정). 버킷·KMS 키·CloudTrail은 Terraform 밖에 있다([`bootstrap/`](../../bootstrap/README.md)).
- **계획과 달랐던 점** — `backend.tf`에 초안에 없던 두 항목을 넣었다. `profile`(backend는 provider 설정을 상속하지 않는다)과
  `kms_key_id`(생략하면 backend가 AES256 헤더를 보내 버킷 기본 암호화를 덮어쓴다). 그리고 prod 파라미터그룹의
  perpetual diff 1건을 `apply_method = pending-reboot`로 해소했다.
- **아직 검증하지 못한 것 2건** — ① Terraform 실행 주체가 아닌 자격증명이 거부되는지(테스트할 두 번째 IAM 주체가 없다)
  ② state 객체의 CloudTrail 데이터 이벤트 기록.
- **롤백** — `backend.tf` 삭제 후 `~/groble-tfstate-backup-20260816/` 복원 → `terraform init -migrate-state`.

---


## 0-a. Terraform 업그레이드 (선행) — ✅ 완료

`use_lockfile`은 **Terraform 1.10+** 에서만 동작한다. 기존 1.5.7은 homebrew-core가 BUSL 전환 시점에 갱신을 멈춘 버전이었다.

- tfenv로 전환하고 **1.15.8** 설치, `.terraform-version`으로 고정. 1.5.7도 tfenv에 남겨둔다
- `required_version`을 `">= 1.0"` → `">= 1.10"` (환경 4곳 + `shared/providers.tf`). `modules/security/waf`는 그대로 — 모듈은 backend를 갖지 않는다
- **업그레이드와 state 이전을 한 번에 하지 않는다.** 업그레이드 후 4개 환경 plan을 먼저 확인한다 (1.5.7과 1.15.8의 plan이 동일함을 확인했다)

> ⚠️ apply를 한 번이라도 하면 state에 `terraform_version`이 기록되어 **구 버전으로는 열 수 없다.** 롤백은 백업 파일로만 가능하다.

## 0-b. drift 해소 — ✅ 완료

`prod`에 파라미터 그룹 drift 1건이 있었다. **apply로는 해소되지 않는 perpetual diff였다** — `innodb_buffer_pool_size`의 `apply_method`가 코드는 `immediate`, AWS는 `pending-reboot`인데, 설정값이 엔진 기본값과 동일해 RDS가 no-op 수정으로 처리하고 기존 ApplyMethod를 유지한다. apply는 `1 changed`로 성공하지만 다음 plan에 같은 변경이 다시 나온다. 코드를 `pending-reboot`로 맞춰 해소했다.

## 0-c. 부트스트랩 리소스 생성 — ✅ 완료

**이 리소스들은 Terraform 밖에서 AWS CLI로 만든다.** "state를 담을 버킷의 state를 어디에 둘 것인가"라는 순환을 피하기 위함이다. state에 들어가지 않으므로 `terraform destroy`로 지워지지 않는다 — 의도된 성질이다.

적용한 정책 원본과 재적용 명령은 [`bootstrap/`](../../bootstrap/README.md)에 있다.

| 리소스 | 값 |
|---|---|
| KMS 키 | `c555c131-6f6a-4422-80f3-e6ec79ff1e3a`, 별칭 `alias/groble/terraform-state`, 365일 자동 순환 |
| state 버킷 | `groble-terraform-state` (ap-northeast-2) |
| 트레일 로그 버킷 | `groble-cloudtrail-logs-538827147369` (SSE-S3, 365일 만료) |
| 트레일 | `groble-audit` (멀티리전, 로그 파일 검증 ON) |

state 버킷 설정 — **시크릿 저장소로 취급한다** (Phase 11 전까지 평문 비밀번호가 담긴 state가 여기 올라간다, 계획서 §2.7):

- versioning ON / BPA 4항목 전부 ON / SSE-KMS + **Bucket Key ON**(KMS 호출 비용 절감)
- lifecycle: 비현행 버전은 **최신 10개 보존**, 그 외 90일 후 삭제. 미완료 멀티파트 7일 정리
- 버킷 정책: HTTP(비TLS) Deny + `aws:PrincipalArn`이 아래 목록에 없으면 Deny
- 트레일 이벤트 셀렉터: 관리 이벤트 전체 + `arn:aws:s3:::groble-terraform-state/` 객체 데이터 이벤트

> ⚠️ **락아웃 방지 — 계획서 원안에서 의도적으로 바꾼 부분.**
> 이 계정에는 SSO 역할이 `AWSReservedSSO_TerraformPowerUser_*` **하나뿐**이다(AdministratorAccess 권한 세트 없음). 계획서대로 정확한 역할 ARN을 박으면, SSO 권한 세트를 재프로비저닝할 때 이름의 랜덤 접미사가 바뀌어 **아무도 state에 접근할 수 없게 된다.** 세 가지로 방어한다:
> ```
> .../AWSReservedSSO_TerraformPowerUser_*       ← 접미사 와일드카드
> .../AWSReservedSSO_AdministratorAccess_*      ← 아직 없는 주체를 미리 허용 (탈출구)
> arn:aws:iam::538827147369:root                ← 최후 수단
> ```
> `AdministratorAccess_*`는 존재하지 않는 주체이므로 현재 실질 권한은 늘지 않는다. 관리자 권한 세트를 나중에 만들면 root 없이 복구할 수 있게 미리 열어두는 것이다.
> KMS 키 정책도 같은 이유로 `Principal`에 역할 ARN을 직접 쓰지 않고 `Principal: root` + `aws:PrincipalArn` 조건 조합을 쓴다.

**부수 효과**: ECS Task Role은 `AmazonS3FullAccess`를 갖고 있어 이 정책 이전에는 state 버킷을 읽을 수 있었다. 이제 거부된다.

**월 비용**: KMS 키 $1 + CloudTrail 데이터 이벤트 $0.10/10만 건 + S3 무시 가능 → **약 $1~2**

## 0-d / 0-e. backend 전환 — ✅ 완료

1. 각 환경에 **`backend.tf`를 별도 파일로** 작성 — `shared` / `prod` / `dev` / `monitoring` 4곳
   (`versions.tf`에 끼워 넣지 않는다. 롤백이 "파일 삭제"로 끝나게 하기 위함)

```hcl
terraform {
  backend "s3" {
    bucket  = "groble-terraform-state"
    key     = "environments/<env>/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "groble-terraform"

    encrypt      = true
    kms_key_id   = "arn:aws:kms:ap-northeast-2:538827147369:key/c555c131-6f6a-4422-80f3-e6ec79ff1e3a"
    use_lockfile = true
  }
}
```

> 계획서 초안에 없던 두 항목을 넣었다.
> - **`profile`** — backend는 provider 설정을 상속하지 않는다. 없으면 기본 자격증명 체인을 타서 인증에 실패한다.
> - **`kms_key_id`** — 생략하면 backend가 `SSE-S3(AES256)` 헤더를 보내 **버킷 기본 암호화(SSE-KMS)를 덮어쓴다.** 애써 만든 KMS 키를 쓰지 않게 되고 감사 추적도 남지 않는다.

2. 환경별로 `terraform init -migrate-state -force-copy` 실행
3. `data "terraform_remote_state"`의 `backend = "local"`을 S3로 변경 — **3곳** (`prod`, `dev`, `monitoring`의 `main.tf`)

> ⚠️ **2와 3은 반드시 연달아 한다.** `-migrate-state`는 로컬 state 파일을 지우지 않고 남긴다. 3을 미루면 세 환경이 S3의 최신 shared state가 아니라 **디스크에 남은 옛 파일을 조용히 계속 읽는다** — 에러가 나지 않아 더 위험하다.

4. 이전 확인 후 로컬 state 파일을 리포지토리 밖으로 옮긴다 (`.terraform/terraform.tfstate`는 backend 설정 포인터이므로 남겨둔다)

---

## 검증

- [x] 각 환경에서 `terraform plan` → **no changes** (4/4)
- [x] 동시에 `terraform plan` 실행 시 **잠금이 걸리는지** — 두 번째가 `Error acquiring the state lock` / S3 `PutObject` `PreconditionFailed`로 거부됨 (조건부 쓰기 기반 네이티브 잠금)
- [x] S3 버킷에 state 객체 4개와 버전이 생성되었는지 — 4개 모두 `ServerSideEncryption: aws:kms`, `.tflock` 객체의 생성·삭제 이력도 확인
- [x] 익명(비인증) 접근이 거부되는지
- [ ] ⚠️ **Terraform 실행 주체가 아닌 자격증명으로 거부되는지** — **미검증**. 계정에 SSO 역할이 하나뿐이고 PowerUser는 IAM 주체를 만들 수 없어 테스트할 두 번째 주체가 없다. 관리자 권한 세트를 프로비저닝하게 되면 그때 확인한다
- [ ] **state 객체의 CloudTrail 데이터 이벤트가 실제로 기록되는지** — 트레일은 로그를 전달 중이고 관리 이벤트는 확인했으나, 객체 데이터 이벤트는 전달 지연으로 이전 직후에는 확인되지 않았다. Phase 1 착수 시 재확인한다

## 롤백

`backend.tf`를 삭제하고 백업해 둔 로컬 state를 복원한 뒤 `terraform init -migrate-state`.
백업 위치: `~/groble-tfstate-backup-20260816/` (이전 직전 사본은 `pre-migration-local/`).

---

[← 이관 절차 목차](README.md) · [다음: Phase 1 — 알람 백스톱 확보 →](./phase-01-alarm-backstop.md)
