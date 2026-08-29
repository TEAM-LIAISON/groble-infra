# 백엔드 협업 문서 (handoff)

> **groble-infra ↔ groble-backend 사이의 요청·질의 문서를 모아둔다.**
> 이 폴더의 문서는 *상대의 회신*을 기다리는 것이 존재 이유다. 회신이 끝나 더 이상
> 아무것도 기다리지 않게 되면 [`closed/`](./closed/)로 옮긴다.

---

## 진행 중 — 회신 대기

| 문서 | 대상 | 요청일 | 상태 | 무엇이 막혀 있나 |
|---|---|---|---|---|
| [egress-ip-allowlist.md](./egress-ip-allowlist.md) | groble-backend | 2026-08-24 | 🔄 진행 중 | **[Phase 3](../runbook/phase-03-nat-gateway.md) 전환의 차단 조건.** 허용목록 관리가 확인되어 **EIP `15.165.223.110` 을 먼저 확보**했다. 현재 **외부 업체 등록 완료 회신 대기** — 등록 전에 전환하면 지속 장애가 된다 |
| [payment-alerts-review.md](./payment-alerts-review.md) | groble-backend | 2026-08-20 | ⏳ 부분 회신 대기 | **A(알림 검수)는 회신 완료** → R1~R9 반영·배포됨. **B(지표 3종 노출) 대기** → 나오면 R10~R14 를 건다. [Phase 2](../runbook/phase-02-observability.md) 완료를 막지는 않는다 |

---

## 종결 — [`closed/`](./closed/)

| 문서 | 대상 | 요청일 | 종결일 | 결과 |
|---|---|---|---|---|
| [backend-jvm-heap-limit.md](./closed/backend-jvm-heap-limit.md) | groble-backend | 2026-08-18 | 2026-08-20 | ✅ PR #826 머지, dev·prod 배포 완료. 힙 상한 2,878 → **900 MiB**. [Phase 7](../runbook/phase-07-prod-asg.md) 차단 해제 |
| [rds-mysql-84-compatibility.md](./closed/rds-mysql-84-compatibility.md) | groble-backend | 2026-08-26 | 2026-08-30 | ✅ 호환성 3건 모두 진행 가능. **2026-08-29 전환 완료**, 구 인스턴스 삭제까지 종결. 확장 지원 과금 $178.56/월 중단. **전환 직후 결제 점검·정기결제 배치 이상 없음 확인** |
| [rds-84-parameter-parity.md](./closed/rds-84-parameter-parity.md) | groble-backend | 2026-08-28 | 2026-08-30 | ✅ 블루/그린 파라미터 차이 4건 수정. **그린이 그대로 전환되어 재검증 항목이 소멸**했다 |
| [rds-84-green-access.md](./closed/rds-84-green-access.md) | groble-backend | 2026-08-28 | 2026-08-30 | 📦 검증용 그린 접속 안내. **그린이 운영으로 전환되어 엔드포인트가 만료**됐다 |

---

## 작성 규칙

- **파일명** — `<주제>-<대상>.md` 형태의 kebab-case. 날짜는 넣지 않는다 (헤더 표에 있다)
- **헤더 표**에 `요청 대상` · `요청자` · `작성일` · `상태` · `관련` 5행을 반드시 둔다
- **상태 어휘는 5개만 쓴다** — 런북과 동일하다

  | 값 | 뜻 |
  |---|---|
  | ⏳ 회신 대기 | 상대의 답을 기다리는 중 |
  | 🔄 진행 중 | 회신을 받아 이쪽에서 반영하는 중 |
  | ✅ 완료 | 반영까지 끝났으나 후속 관찰이 남음 |
  | 📦 종결 | 더 이상 기다릴 것도 할 것도 없음 → `closed/`로 이동 |
  | ⬜ 미착수 | 문서만 써두고 아직 보내지 않음 |

- **`closed/`로 옮길 때** — 헤더에 종결일과 결과를 적고, 문서 맨 앞에 "종결된 요청서다"를 밝힌다.
  그리고 **이 README 의 표 두 개를 갱신한다.** 옮기면 상대경로 깊이가 한 단 늘어난다는 점에 주의할 것
- **상대에게 보내는 문서다.** 인프라 내부 은어를 쓰지 말고, 질문은 번호를 붙여 답하기 쉽게 만든다
