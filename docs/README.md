# groble-infra 문서

> 인프라 문서의 진입점. **어떤 문서를 언제 여는가**만 정리한다. 내용은 각 문서에 있다.

---

## 무엇을 찾고 있나

| 질문 | 문서 |
|---|---|
| 지금 배포되어 있는 게 뭔가? | [`../CLAUDE.md`](../CLAUDE.md) — **As-Is 만** 기술한다 |
| 무엇을 왜 바꾸려는 건가? | [plan/infra-ha-improvement-plan.md](./plan/infra-ha-improvement-plan.md) — 설계·결정 근거 |
| 어떤 순서로 옮기나? 지금 어디까지 왔나? | [runbook/README.md](./runbook/README.md) — **진행 상태의 단일 진실** |
| 특정 Phase 를 실제로 어떻게 하나? | [runbook/](./runbook/) — Phase 당 1개 파일 |
| 이번 범위 밖으로 미뤄둔 건? | [plan/infra-future-improvements.md](./plan/infra-future-improvements.md) |
| 백엔드에 뭘 물어놨고 답이 왔나? | [handoff/README.md](./handoff/README.md) |
| 모니터링 설정은 어디서 바꾸나? | [reference/monitoring-config-baking.md](./reference/monitoring-config-baking.md) — 이 리포가 아니라 `groble-images` |
| **EC2·RDS 에 어떻게 접속하나?** | [reference/developer-access.md](./reference/developer-access.md) — SSM 으로 VPN 없이. **백엔드 개발자용** |

---

## 폴더 구조 — 폴더는 *종류*, 상태는 *메타데이터*

**네 갈래다.** 폴더 하나가 곧 "이 문서는 무엇인가"에 답한다.

```
docs/
  README.md         ← 여기. 진입점

  plan/             설계·백로그 — 무엇을 왜
    infra-ha-improvement-plan.md    설계·결정 근거
    infra-future-improvements.md    이번 범위 밖으로 미뤄둔 것

  runbook/          실행 — 어떤 순서로 어떻게. 완료된 것도 여기 남는다
    README.md       목차 · 공통 원칙 · 부록. **진행 상태의 단일 진실**
    phase-00..12.md Phase 당 1개 파일
    adhoc/          Phase 순서와 무관한 단발 작업 (예: RDS 8.4 업그레이드)
                    — Phase 와 같은 "실행 절차"다. 번호가 없고 `겹치는 Phase` 행이 그 자리를 대신한다

  handoff/          통신 — 상대(백엔드)가 있는 문서. 회신 대기 중인 것
    closed/         회신이 끝나 더 기다릴 게 없는 것

  reference/        상시 참조 — 수명이 없다. 대상이 사라질 때 함께 사라진다
    developer-access.md            SSM 접속 경로 (백엔드 개발자용)
    monitoring-config-baking.md    config baking 구조
```

**갈래를 가르는 기준은 "수명"이다.**

| 갈래 | 언제 끝나나 |
|---|---|
| `plan/` | 마이그레이션이 끝나면 As-Is 로 흡수된다 |
| `runbook/` | 개별 문서는 완료되지만 **기록으로 남는다** |
| `handoff/` | 상대가 답하면 끝난다 → `closed/` |
| `reference/` | 끝나지 않는다. 대상이 사라질 때만 지운다 |

**완료된 Phase 문서를 옮기지 않는 이유**가 두 가지 있다.

1. **완료된 런북은 archive 가 아니라 "지금 배포된 것의 기록"이다.** Phase 0·1 문서는 현재 state 백엔드와
   알람 구성이 어떻게 만들어졌고 어떻게 되돌리는지를 담은 유일한 문서다. 대신 문서 맨 앞에
   **`## ✅ 완료 요약`** 블록을 두어 "따라 할 절차"가 아니라 "기록"임을 밝힌다.
2. **Phase 00~12 가 한 폴더에 순서대로 있어야** 남은 일이 한눈에 보인다.

`handoff/`에만 `closed/`가 있는 것은, 요청서는 상대가 답하면 **실제로 수명이 끝나는** 문서이기 때문이다.

---

## 상태 어휘

**문서 헤더 표의 `상태` 행과 [목차 표](./runbook/README.md)에 같은 단어만 쓴다.**

| 값 | 뜻 |
|---|---|
| ⬜ 미착수 | 아직 시작하지 않음 |
| 🔄 진행 중 | 작업 중 (무엇이 남았는지 함께 적는다) |
| ⏳ 회신 대기 | 상대(주로 백엔드)의 답을 기다리는 중 |
| ✅ 완료 | 배포·검증 완료 |
| 📦 종결 | 더 이상 할 것이 없음 (handoff 전용 → `closed/`) |

---

## 문서를 고칠 때

- **상태가 바뀌면 두 곳을 함께 고친다** — 해당 문서의 헤더 `상태` 행과 [목차 표](./runbook/README.md).
  handoff 라면 [handoff/README.md](./handoff/README.md)도 함께.
- **Phase·adhoc 이 완료되면** 문서를 옮기지 말고, 맨 앞(헤더 표 바로 뒤)에 `## ✅ 완료 요약` 블록을 넣는다.
  *배포된 것 · 검증 결과 · 계획과 달랐던 점 · 검증하지 못한 것 · 롤백* 을 적는다.
  **다시 쓸 절차가 남아 있으면 "재사용할 절차" 항목으로 어느 단계인지 가리킨다**
  (예: [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 의 E·F — 다음 모니터링 노드 교체에 그대로 쓴다).
- **완료 시 본문의 시제를 함께 고친다.** 완료 문서에 "~한다 / ~할 것" 이 남아 있으면 다음 사람이
  절차서로 읽는다. **미완 체크박스는 지우지 말고 "하지 않았다 + 그래서 어떻게 됐다"로 남긴다** —
  건너뛴 단계가 어떤 대가를 치렀는지가 다음 실행의 근거다.
- **adhoc 문서에는 헤더 표에 `겹치는 Phase` 행을 둔다.** 번호가 없는 대신 이 행이 "언제 끼워 넣을 수
  있는가"를 답한다. 새로 만들면 [이관 절차 목차의 adhoc 표](./runbook/README.md#adhoc--phase-순서와-무관한-단발-작업)에도 한 줄 추가한다.
- **제목에 `{#custom-id}` 를 쓰지 않는다.** **GitHub 는 이 문법을 지원하지 않고 리터럴 텍스트로 렌더한다** —
  앵커가 안 잡힐 뿐 아니라 제목에 `{#urgent-1}` 이 그대로 보인다. 링크는 GitHub 가 실제로 만드는
  슬러그를 쓴다: **소문자화 → 문장부호·기호·이모지 제거 → 공백 1개당 하이픈 1개**
  (공백을 합치지 않는다 — `A — B` 는 `a--b` 가 되고, 앞의 이모지는 선행 하이픈을 남긴다).
- **제목을 고치면 그 제목을 가리키던 앵커가 조용히 깨진다.** 링크는 살아 있고 페이지는 열리는데
  엉뚱한 위치로 간다. 제목을 고쳤으면 아래 검사를 돌릴 것.
- **파일을 옮기거나 제목을 고치면 아래로 전수 검사한다.** 이 문서 트리에는 링크가 **500개 가까이**
  있고(경로 430 · 앵커 69), 경로 쪽은 `.md` 뿐 아니라 디렉터리(`./runbook/`)와
  소스파일(`../../modules/.../main.tf#L28`)도 가리킨다. `grep` 으로는 깊이가 바뀐 링크도,
  깨진 앵커도 잡히지 않는다.

  ```bash
  python3 - <<'EOF'
  import os,re,unicodedata,urllib.parse,collections
  def slug(h):
      h=h.strip().lower()
      return ''.join(c for c in h if c in '-_ ' or unicodedata.category(c)[0] in 'LN').replace(' ','-')
  def heads(t):
      seen=collections.Counter(); out=set()
      for m in re.finditer(r'^#{1,6}\s+(.*)$',t,re.M):
          b=slug(m.group(1)); n=seen[b]; seen[b]+=1
          out.add(b if n==0 else f"{b}-{n}")
      return out
  fs=[os.path.normpath(os.path.join(r,f)) for r,_,g in os.walk('.') if not r.startswith('./.git')
      for f in g if f.endswith('.md')]
  H={p:heads(open(p,encoding='utf-8',errors='replace').read()) for p in fs}
  bad=[]
  for p in fs:
      for m in re.finditer(r'\]\(([^)\s]+)\)', open(p,encoding='utf-8',errors='replace').read()):
          t=m.group(1)
          if t.startswith(('http://','https://','mailto:')): continue
          path,_,anc=t.partition('#')
          tgt=os.path.normpath(os.path.join(os.path.dirname(p),urllib.parse.unquote(path))) if path else p
          if path and not os.path.exists(tgt): bad.append(f"경로 {p}: {t}"); continue
          if anc and tgt in H and urllib.parse.unquote(anc) not in H[tgt]: bad.append(f"앵커 {p}: {t}")
  print("\n".join(bad) or "OK")
  EOF
  ```

  ⚠️ **링크 텍스트는 이 검사에 안 걸린다.** 링크 라벨(대괄호 안)에 옛 경로가 백틱으로 박혀 있으면
  **링크는 멀쩡히 열리는데 읽는 사람이 속는다.** 아래로 함께 볼 것.

  ```bash
  grep -rn --include='*.md' '<옛-파일명>' .
  ```
- **`CLAUDE.md` 는 As-Is 만 담는다.** 계획이나 진행 중인 것을 거기에 적지 않는다 —
  진행 상태는 목차 표가 단일 진실이고, `CLAUDE.md` 에는 그 요약과 링크만 둔다.
