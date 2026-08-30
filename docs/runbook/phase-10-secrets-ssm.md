# Phase 10 — Secrets를 SSM Parameter Store로

> [← Phase 9](./phase-09-access-path.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 11 →](./phase-11-cleanup.md)

| | |
|---|---|
| **상태** | ⬜ 미착수 |
| **목적** | 비밀값이 Terraform state·태스크 정의 JSON·ECS 콘솔에 평문으로 남는 상태를 해소한다 |
| **사용자 영향** | 없음 (rolling 재배포) |
| **시점** | [Phase 5]((./phase-05-deployment-controller.md))의 rolling 배포가 충분히 안정화된 뒤. 태스크 정의를 건드리므로 다른 변경과 겹치지 않게 한다 |
| **되돌리기** | 이전 태스크 정의 |

---

## 절차

1. **파라미터를 AWS CLI로 생성** (Terraform으로 만들지 않는다 — state에 평문이 다시 들어간다)
   ```bash
   aws ssm put-parameter --name /groble/prod/db-password --type SecureString --value '<값>' --key-id <kms-key>
   ```
2. 태스크 정의를 `environment` → `secrets`로 변경
   ```hcl
   secrets = [
     { name = "DB_PASSWORD", valueFrom = "arn:aws:ssm:...:parameter/groble/prod/db-password" }
   ]
   ```
3. **Task Execution Role에 `ssm:GetParameters` + KMS `Decrypt` 권한을 추가한다** ⚠️

   > 흔한 오해: 현재 `ssm:GetParameters`(`parameter/groble/*`)는 **Task Role**에 인라인으로 붙어 있고,
   > **Execution Role에는 없다**(`AmazonECSTaskExecutionRolePolicy` + `AmazonEC2ContainerRegistryPowerUser`뿐).
   > 태스크 정의의 `secrets` / `valueFrom`은 **Execution Role 권한으로 해석**되므로,
   > 권한을 추가하지 않으면 태스크가 `ResourceInitializationError`로 기동에 실패한다.
4. rolling 재배포
5. Grafana `GF_SECURITY_ADMIN_PASSWORD`도 동일하게 처리
6. Terraform 변수에서 평문 비밀값 제거

## 검증

- [ ] 태스크 정의 JSON에 평문 비밀값이 없는지
- [ ] 앱이 정상 기동하고 DB 연결이 되는지
- [ ] state 파일에서 비밀값이 사라졌는지 (`terraform state pull | grep -i password`)

## 롤백

이전 태스크 정의 리비전으로 `update-service`.

---

[← Phase 9 — 접근 경로 정리](./phase-09-access-path.md) · [이관 절차 목차](../infra-ha-migration-runbook.md) · [다음: Phase 11 — 잔재 정리 및 문서 갱신 →](./phase-11-cleanup.md)
