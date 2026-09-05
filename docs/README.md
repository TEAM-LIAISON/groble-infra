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

### 완료된 것을 따로 빼는 기준 — `closed/` 는 예외지 규칙이 아니다

이 저장소의 기본 원칙은 **"폴더는 종류, 상태는 메타데이터"** 다. 완료 여부는 폴더가 아니라
목차 표의 ✅ · 문서 헤더의 `상태` 행 · 맨 앞의 `## ✅ 완료 요약` 이 답한다.

`handoff/closed/` 는 그 원칙의 **예외**이며, 예외가 정당한 조건은 하나다 —
**목록이 더 이상 한눈에 읽히지 않을 때.** 세 갈래를 같은 기준으로 재면 이렇게 갈린다.

| | 늘어나나 | 순서가 있나 | 따로 빼나 |
|---|---|---|---|
| `handoff/` | **무한** | 없음 | ✅ `closed/` — 이미 필요했다 |
| `runbook/adhoc/` | **무한** | 없음 | ⏳ 10개 넘으면 연도별 (아래 트리거) |
| `runbook/phase-*` | **13개에서 닫힌다** | **있다** | ❌ **영원히 불필요** |

`handoff/README.md` 가 답하는 것은 "지금 무엇을 기다리고 있나"라는 **행동을 요구하는 질문**이다.
종결된 요청서는 진행 중인 것과 파일 모양·헤더가 같아 섞이면 구분이 안 된다. 그래서 물리적 분리가 필요했다.

**Phase 는 그 조건에 해당하지 않는다.**

1. **목록 자체가 계획이다.** `phase-00` ~ `phase-12` 가 한 폴더에 번호순으로 있는 것이 곧 읽을거리다.
   완료분을 빼면 순서가 두 폴더로 갈라지고, **번호는 여전히 순서를 주장하는데 파일시스템은 그것을 보여주지 않는 상태**가 된다.
2. **완료된 런북은 archive 가 아니라 "지금 배포된 것의 기록"이다.** Phase 0·1 문서는 현재 state 백엔드와
   알람 구성이 어떻게 만들어졌고 어떻게 되돌리는지를 담은 **유일한** 문서다.
3. **"끝났다"가 사실이 아니다.** [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 의 E·F 와
   [Phase 9](./runbook/phase-09-prod-asg.md) 의 instance refresh 는 **앞으로도 반복해서 쓰는 절차**다.
   `closed/` 에 넣으면 문서가 거짓말을 하게 된다.

> **[Phase 12](./runbook/phase-12-cleanup.md) 까지 전부 완료돼도 `phase-*` 는 `runbook/` 에 그대로 둔다.**
> 그때 바뀌는 것은 위치가 아니라 **여는 이유**이며, 그래서 Phase 12 의 작업은 이동이 아니라
> 「앞으로도 쓰는 절차」 색인과 성격 재선언이다.

---

## 마이그레이션이 끝나면 — 문서는 어떻게 되나

**아무것도 삭제하지 않는다.** 대신 성격이 바뀌는 시점에 **표시와 색인**을 붙인다.

### 문서가 생기는 흐름이 바뀐다

```
plan/infra-future-improvements.md   ← 백로그. 끝나지 않는 유일한 계획 문서
        │  항목 하나를 착수
        ▼
runbook/adhoc/<작업>.md             ← 앞으로 생기는 실행 문서는 전부 여기
        │  백엔드 협조가 필요하면
        ▼
handoff/<질의>.md ──► closed/
        │  완료
        ▼
✅ 완료 요약  +  CLAUDE.md(As-Is) 갱신
```

**`phase-00` ~ `phase-12` 는 닫힌 집합이 된다.** 13번째 Phase 는 없다.
살아 있는 폴더는 `adhoc/` 과 `handoff/` 둘뿐이다.

### 갈래별로 무엇이 달라지나

| 갈래 | 마이그레이션 종료 시 |
|---|---|
| `runbook/phase-*` | **런북(따라 할 절차) → 결정 기록(왜 이렇게 생겼는지)** 으로 성격이 바뀐다. 삭제하지 않고 폴더도 옮기지 않는다 — [아래 참조](#runbook-을-history-로-개명하지-않는-이유) |
| `runbook/adhoc/` | 여기만 계속 늘어난다 |
| `handoff/closed/` | 계속 쌓인다. **그게 맞다** — [아래 참조](#closed-를-비우지-않는-이유) |
| `plan/infra-ha-improvement-plan.md` | To-Be 가 As-Is 가 되어 내용은 `CLAUDE.md` 로 흡수된다. 문서는 **결정 근거**로 남는다 — 헤더에 `✅ 실현됨` 을 달아 성격을 재선언한다 |
| `plan/infra-future-improvements.md` | **끝나지 않는다.** 오히려 여기서부터 주 문서가 된다 |
| `reference/` | 변화 없다. 대상이 사라질 때만 지운다 |

### `runbook/` 을 `history/` 로 개명하지 않는 이유

**일부는 여전히 절차이기 때문이다.** [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 의 E·F(모니터링 노드 교체)와
[Phase 9](./runbook/phase-09-prod-asg.md) 의 instance refresh 는 앞으로도 반복해서 쓴다. 통째로 "역사"가 아니다.
링크 500개를 다시 건드리는 비용도 있다.

→ 대신 **[runbook/README.md](./runbook/README.md) 상단에 「앞으로도 쓰는 절차」 색인을 만든다.**
각 문서의 `## ✅ 완료 요약` 안에 둔 **"재사용할 절차"** 항목을 모으면 된다.
나머지는 기록으로 가라앉는다. (Phase 12 의 작업이다)

### `closed/` 를 비우지 않는 이유

**종결된 요청서는 결정의 근거다.** 예를 들어
[`closed/jvm-dns-cache.md`](./handoff/closed/jvm-dns-cache.md) 는 "원인은 DNS 캐시가 아니라
커넥션 풀 수명"이라는 **정정**을 담고 있고, 그것이 [Phase 4](./runbook/phase-04-monitoring-node-rebuild.md) 의
E·F 순서를 뒤집은 근거다. 지우면 왜 그 순서인지 설명할 수 없게 된다.

**쌓이는 것 자체는 문제가 아니었다.** 문제는 *진행 중인 것과 섞이는 것*이었고
`closed/` 폴더가 이미 그것을 해결했다 — [handoff/README.md](./handoff/README.md) 는 대기 중을 위에,
종결을 아래에 둔다. 종결분이 60개가 돼도 이 구조는 무너지지 않는다.

### 낡은 문서 — 판정 기준은 "참조 수"가 아니라 "지금도 참인가"

**참조가 0인 것은 삭제 근거가 아니다.** 낡은 문서의 실제 피해는 자리를 차지하는 것이 아니라
**읽는 사람을 속이는 것**이고, 그것은 인용될수록 위험하다.

| 상태 | 조치 |
|---|---|
| 참이고 인용된다 | 그대로 |
| 참이지만 아무도 안 본다 | **그대로 둔다.** 언젠가 "왜 이렇게 됐지?" 에 답한다 |
| **거짓이 됐다** | **지우지 않는다.** 맨 앞에 무효 표시를 달고 진실을 링크로 넘긴다 (아래) |

```markdown
> ⚠️ **이 문서는 더 이상 유효하지 않다.** <무엇이 바뀌었는지 한 줄>
> 지금의 사실은 [<문서>](<링크>) 에 있다. 이 문서는 <날짜> 시점의 기록으로 남긴다.
```

지우면 그 사이의 **결정 이력까지 사라진다.** 무효 표시는 남기고 진실은 링크로 넘긴다.

> 실제 사례: `phase-02` 가 "dev MySQL 은 Phase 9 에서 RDS 로 이관된다"고 적고 있었으나
> 실제로는 [Phase 5](./runbook/phase-05-dev-rds.md) 에서 이미 갔다(2026-09-01). 참조가 있어서 위험했지 없어서 위험한 것이 아니었다.

### 개수는 언제 문제가 되나 — 트리거

문서 수 자체는 비용이 아니다. **한 폴더의 목록이 한눈에 안 읽히는 순간**이 비용이다.

| 트리거 | 조치 |
|---|---|
| `runbook/adhoc/` 이 **10개** 초과 | [runbook/README.md](./runbook/README.md) 의 adhoc 표를 연도별로 나눈다 |
| `handoff/closed/` 가 **30개** 초과 | `handoff/README.md` 의 종결 표를 연도별로 접는다 |
| **분기 1회** | `CLAUDE.md` 와 완료 문서의 서술이 실제 배포 상태와 어긋나는지 점검. 어긋난 것은 위 무효 표시 |

**증가 속도 실측** — `docs/` 의 `.md` 30개 중 **18개가 2026-08 한 달에 생겼다**(마이그레이션 설계·착수).
그 전후 달은 각각 1개다. 즉 지금 속도는 특수 상황이며, 정상 운영에서는
adhoc 과 그에 딸린 handoff 를 합쳐 **연 10개 안팎**으로 본다. 그중 "진행 중"은 항상 5개 미만이다 —
`closed/` 와 `✅ 완료 요약` 이 나머지를 걸러 주기 때문이다.

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
- **문서가 거짓이 되면 지우지 말고 무효 표시를 단다.** 맨 앞에
  `> ⚠️ **이 문서는 더 이상 유효하지 않다.** … 지금의 사실은 [X](…) 에 있다` 를 두고 진실을 링크로 넘긴다.
  지우면 그 사이의 결정 이력까지 사라진다 — [마이그레이션이 끝나면](#낡은-문서--판정-기준은-참조-수가-아니라-지금도-참인가) 참조.
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
  def body(p):                      # 코드 블록·인라인 코드는 링크가 아니다
      t=open(p,encoding='utf-8',errors='replace').read()
      t=re.sub(r'^```.*?^```','',t,flags=re.M|re.S)
      return re.sub(r'`[^`\n]*`','',t)
  fs=[os.path.normpath(os.path.join(r,f)) for r,_,g in os.walk('.') if not r.startswith('./.git')
      for f in g if f.endswith('.md')]
  H={p:heads(open(p,encoding='utf-8',errors='replace').read()) for p in fs}
  bad=[]
  for p in fs:
      for m in re.finditer(r'\]\(([^)\s]+)\)', body(p)):
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
