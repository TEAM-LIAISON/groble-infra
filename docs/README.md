# groble-infra 문서

> 인프라 문서의 진입점. **어떤 문서를 언제 여는가**만 정리한다. 내용은 각 문서에 있다.

---

## 무엇을 찾고 있나

| 질문 | 문서 |
|---|---|
| 지금 배포되어 있는 게 뭔가? | [`../CLAUDE.md`](../CLAUDE.md) — **As-Is 만** 기술한다 |
| 무엇을 왜 바꾸려는 건가? | [infra-ha-improvement-plan.md](./infra-ha-improvement-plan.md) — 설계·결정 근거 |
| 어떤 순서로 옮기나? 지금 어디까지 왔나? | [infra-ha-migration-runbook.md](./infra-ha-migration-runbook.md) — **진행 상태의 단일 진실** |
| 특정 Phase 를 실제로 어떻게 하나? | [runbook/](./runbook/) — Phase 당 1개 파일 |
| 이번 범위 밖으로 미뤄둔 건? | [infra-future-improvements.md](./infra-future-improvements.md) |
| 백엔드에 뭘 물어놨고 답이 왔나? | [handoff/README.md](./handoff/README.md) |
| 모니터링 설정은 어디서 바꾸나? | [monitoring-config-baking.md](./monitoring-config-baking.md) — 이 리포가 아니라 `groble-images` |
| **EC2·RDS 에 어떻게 접속하나?** | [developer-access.md](./developer-access.md) — SSM 으로 VPN 없이. **백엔드 개발자용** |

---

## 폴더 구조 — 폴더는 *종류*, 상태는 *메타데이터*

```
docs/
  infra-ha-improvement-plan.md      설계 — 무엇을 왜
  infra-ha-migration-runbook.md     실행 목차 · 공통 원칙 · 부록
  infra-future-improvements.md      백로그 — 이번 범위 밖
  monitoring-config-baking.md       참조 — config baking 구조
  developer-access.md               참조 — SSM 접속 경로 (백엔드 개발자용)

  runbook/          Phase 00~12. 완료된 것도 여기 남는다
    adhoc/          Phase 순서와 무관한 단발 작업 (예: RDS 8.4 업그레이드)
                    — Phase 와 같은 "실행 절차"다. 번호가 없고 `겹치는 Phase` 행이 그 자리를 대신한다

  handoff/          백엔드에 보낸 요청·질의 — 회신 대기 중인 것
    closed/         회신이 끝나 더 기다릴 게 없는 것
```

**완료된 Phase 문서를 옮기지 않는 이유**가 두 가지 있다.

1. **완료된 런북은 archive 가 아니라 "지금 배포된 것의 기록"이다.** Phase 0·1 문서는 현재 state 백엔드와
   알람 구성이 어떻게 만들어졌고 어떻게 되돌리는지를 담은 유일한 문서다. 대신 문서 맨 앞에
   **`## ✅ 완료 요약`** 블록을 두어 "따라 할 절차"가 아니라 "기록"임을 밝힌다.
2. **Phase 00~12 가 한 폴더에 순서대로 있어야** 남은 일이 한눈에 보인다.

`handoff/`에만 `closed/`가 있는 것은, 요청서는 상대가 답하면 **실제로 수명이 끝나는** 문서이기 때문이다.

---

## 상태 어휘

**문서 헤더 표의 `상태` 행과 [목차 표](./infra-ha-migration-runbook.md)에 같은 단어만 쓴다.**

| 값 | 뜻 |
|---|---|
| ⬜ 미착수 | 아직 시작하지 않음 |
| 🔄 진행 중 | 작업 중 (무엇이 남았는지 함께 적는다) |
| ⏳ 회신 대기 | 상대(주로 백엔드)의 답을 기다리는 중 |
| ✅ 완료 | 배포·검증 완료 |
| 📦 종결 | 더 이상 할 것이 없음 (handoff 전용 → `closed/`) |

---

## 문서를 고칠 때

- **상태가 바뀌면 두 곳을 함께 고친다** — 해당 문서의 헤더 `상태` 행과 [목차 표](./infra-ha-migration-runbook.md).
  handoff 라면 [handoff/README.md](./handoff/README.md)도 함께.
- **Phase·adhoc 이 완료되면** 문서를 옮기지 말고, 맨 앞(헤더 표 바로 뒤)에 `## ✅ 완료 요약` 블록을 넣는다.
  *배포된 것 · 검증 결과 · 계획과 달랐던 점 · 검증하지 못한 것 · 롤백* 을 적는다.
  **다시 쓸 절차가 남아 있으면 "재사용할 절차" 항목으로 어느 단계인지 가리킨다**
  (예: [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 의 E·F — 다음 모니터링 노드 교체에 그대로 쓴다).
- **완료 시 본문의 시제를 함께 고친다.** 완료 문서에 "~한다 / ~할 것" 이 남아 있으면 다음 사람이
  절차서로 읽는다. **미완 체크박스는 지우지 말고 "하지 않았다 + 그래서 어떻게 됐다"로 남긴다** —
  건너뛴 단계가 어떤 대가를 치렀는지가 다음 실행의 근거다.
- **adhoc 문서에는 헤더 표에 `겹치는 Phase` 행을 둔다.** 번호가 없는 대신 이 행이 "언제 끼워 넣을 수
  있는가"를 답한다. 새로 만들면 [이관 절차 목차의 adhoc 표](./infra-ha-migration-runbook.md#adhoc--phase-순서와-무관한-단발-작업)에도 한 줄 추가한다.
- **파일을 옮기면 상대경로가 깨진다.** 이 문서 트리에는 상대링크가 150개 넘게 있다.
  이동 후 `grep -rn '](.*\.md' docs` 로 확인할 것.
- **`CLAUDE.md` 는 As-Is 만 담는다.** 계획이나 진행 중인 것을 거기에 적지 않는다 —
  진행 상태는 목차 표가 단일 진실이고, `CLAUDE.md` 에는 그 요약과 링크만 둔다.
