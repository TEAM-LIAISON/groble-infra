# [작업 요청] groble-backend — JVM 힙 상한을 컨테이너 리밋에 맞춰 고정

| | |
|---|---|
| **요청 대상** | groble-backend (Dockerfile) |
| **요청자** | 인프라 (groble-infra, HA 개선 Phase 2 작업 중 발견) |
| **작성일** | 2026-08-18 |
| **긴급도** | **높음 — 인프라 Phase 7(ASG 전환)의 차단 조건** |
| **영향 범위** | prod·dev API 컨테이너 양쪽 |

---

## 1. 한 줄 요약

`Dockerfile`의 `-XX:MaxRAMPercentage=75.0`이 **컨테이너 메모리 리밋이 아니라 EC2 호스트 전체 RAM 기준으로 적용**되고 있어,
JVM이 실제 허용치(1,500 MiB)의 **약 2배(2,878 MiB)를 자기 예산으로 알고 동작**합니다.
지금은 노드의 스왑파일이 이를 흡수해 죽지 않고 있으나, **인프라 Phase 7에서 스왑이 사라지면 prod API가 OOM으로 종료됩니다.**
힙 상한을 명시적으로 고정해 주시기를 요청드립니다.

---

## 2. 근거 — 실측 데이터

**출처**: 운영 Prometheus (`10.0.1.193:9090`), 2026-08-18 기준 **직전 15일**, 1분 해상도.
prod API 태스크(`ecs-groble-prod-task-*-groble-prod-spring-api-*`) 및 `job="groble-api"`.

### 2.1 JVM이 믿는 힙 상한 vs 실제 컨테이너 리밋

| 항목 | 값 |
|---|---|
| JVM 힙 상한 (`jvm_memory_max_bytes{id="G1 Old Gen"}`) | **2,878 MiB** |
| 컨테이너 하드리밋 (`container_spec_memory_limit_bytes`) | **1,500 MiB** (15일간 변동 없음) |
| EC2 노드 전체 RAM (`node_memory_MemTotal_bytes`, t3.medium) | **3,837 MiB** |

> `3,837 MiB × 0.75 = 2,877.75 MiB` — 관측된 2,878 MiB와 정확히 일치합니다.
> 즉 `MaxRAMPercentage=75.0`이 **호스트 RAM에 적용**되었습니다. 컨테이너 리밋 기준이었다면 `1,500 × 0.75 = 1,125 MiB`여야 합니다.
> dev 태스크도 동일하게 2,878 MiB로 관측됩니다 (같은 이미지·같은 사양 노드).

### 2.2 그 결과 — 힙이 컨테이너 리밋을 넘어섭니다

| 항목 (prod, 15일) | 값 |
|---|---|
| heap **used** 중앙값 | 522 MiB |
| heap **used** p99 | 1,362 MiB |
| heap **used** 최대 | **1,602 MiB** ← 컨테이너 리밋 초과 |
| heap **committed** 최대 | **1,766 MiB** ← 컨테이너 리밋 초과 |
| heap + nonheap **committed** 최대 | **2,166 MiB** |
| nonheap **committed** 최대 | 400 MiB |

라이브 객체 중앙값은 **522 MiB뿐**인데 커밋은 1,766 MiB까지 갔습니다.
G1이 상한을 2,878 MiB로 알고 있어 **메모리 압박을 느끼지 못해 회수를 미루고 힙만 계속 커밋**하기 때문입니다.

### 2.3 안 죽는 이유 — 스왑이 받아내고 있습니다

노드 user_data(`prod_user_data.sh`)가 만드는 **1 GiB 스왑파일**이 초과분을 흡수하고 있습니다.

| 항목 (prod 노드, 15일) | 값 |
|---|---|
| 스왑 총량 / **최대 사용** | 1,024 MiB / **947 MiB** |
| 컨테이너 스왑 사용 최대 | 915 MiB |
| 스왑 I/O 최대 | **pswpin 1,211 · pswpout 1,380 pages/s** (≈5 MiB/s) |
| `MemAvailable` 최소 | **365 MiB** (3,837 MiB 노드에서) |
| OOM kill 횟수 | **0회** |

**즉 JVM 힙의 일부가 디스크(스왑)에 올라간 채로 서비스 중입니다.**

### 2.4 이미 성능 대가를 내고 있습니다

| 항목 | 값 |
|---|---|
| **GC pause (`jvm_gc_pause_seconds_max`)** | p50 **8 ms** · p99 **145 ms** · **최대 2,584 ms** |
| GC 오버헤드 최대 (`jvm_gc_overhead`) | 1.52% |

**GC는 평소엔 건강하다(p50 8 ms, 오버헤드 1.5%). 문제는 드물게 발생하는 초 단위 정지다** — 최대 2.6초.
이 정지는 스왑 때문이라고 볼 근거가 있다. GC pause 상위 10개 시점을 같은 시각의 스왑인 속도와 대조하면
상위 구간은 `pswpin` 22~211 pages/s 를 동반하는 반면, **pause 하위 200개 구간의 스왑인 중앙값은 0**이다.
큰 수집이 스왑아웃된 힙 페이지를 밟을 때만 초 단위로 멈추는 것으로, 기전이 일관된다.

2.6초 정지는 사용자에게 그대로 노출되고, ALB 헬스체크·타임아웃을 건드릴 수 있는 크기다.

> 📌 **정정 (2026-08-19).** PR #826 본문에 인용된 "GC 평균 pause 최대 463 ms"는 취약한 식
> (`rate(sum)/rate(count)`, 수집 없는 구간에서 `inf`/`NaN`)에서 나온 값이라 이 표로 대체합니다.
> **수정 방향과 `-Xmx900m` 결정은 그대로 유효합니다** — 최대 정지가 463 ms 가 아니라 2,584 ms 로
> 오히려 더 나빴습니다.

### 2.5 컨테이너 메모리는 캐시가 아니라 실사용입니다

| 항목 (prod, 15일) | 값 |
|---|---|
| 컨테이너 RSS (anonymous) p50 / p90 / max | 1,274 / 1,484 / **1,493 MiB** |
| 컨테이너 page cache p99 | **108 MiB** |
| RSS가 1,400 MiB를 넘는 시간 비율 | **47.6%** |

리밋을 채우고 있는 것은 회수 가능한 페이지 캐시가 아니라 **거의 전부 anonymous 메모리**입니다.
(인프라 측이 당초 "대부분 페이지 캐시일 것"으로 가정했으나, 이 측정으로 반증되었습니다.)

---

## 3. 왜 지금 고쳐야 하나 — Phase 7 차단 조건

인프라는 현재 단일 EC2(pet) → **ASG 기반 다중 인스턴스(cattle)** 구조로 이관 중입니다 (Phase 7).

- 지금 OOM을 막고 있는 스왑파일은 **AMI 기본 기능이 아니라 현재 노드의 `user_data` 스크립트가 만드는 것**입니다.
- Phase 7에서 노드는 **ECS-optimized AL2023 AMI + Launch Template**으로 교체되며, 이 스왑파일은 사라집니다.
- **JVM 설정을 그대로 둔 채 노드를 교체하면, 새 ASG 노드에서 prod API가 OOM kill로 종료됩니다.**
- 하필 마이그레이션 도중이라 원인 판별이 가장 어려운 시점입니다.

추가로, 이 값이 고쳐지기 전에는 인프라가 **Phase 7/8의 `memoryReservation`(태스크 배치 기준값)을 확정할 수 없습니다.**
현재 관측되는 1.5 GiB는 앱의 실제 요구량이 아니라 잘못된 JVM 상한이 만들어낸 값이라, 이 숫자로 사이징하면 오설정을 인프라에 고착시키게 됩니다.

---

## 4. 요청 사항

### 4.1 현재 코드

`groble-backend/Dockerfile:13`

```dockerfile
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-Dcom.amazonaws.sdk.disableEc2Metadata=true", "-Dspring.profiles.active=${PROFILES}", "-Dserver.env=${ENV}", "-jar", "app.jar"]
```

### 4.2 수정안 — 두 가지 방식

**컨테이너 리밋 인식이 왜 실패하는지는 아직 규명하지 못했습니다.** 따라서 원인과 무관하게 결정적인
**명시적 `-Xmx`** 로 가는 것을 권장드립니다 (`MaxRAMPercentage`는 제거).

#### 방식 A — 최소 변경 (Dockerfile에 직접 고정)

```dockerfile
ENTRYPOINT ["java", \
  "-Xms512m", "-Xmx900m", \
  "-XX:+ExitOnOutOfMemoryError", \
  "-Dcom.amazonaws.sdk.disableEc2Metadata=true", \
  "-Dspring.profiles.active=${PROFILES}", \
  "-Dserver.env=${ENV}", \
  "-jar", "app.jar"]
```

#### 방식 B — 권장 (`JAVA_OPTS`로 분리, 값은 인프라가 주입)

```dockerfile
ENV JAVA_OPTS="-Xms512m -Xmx900m -XX:+ExitOnOutOfMemoryError"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS \
  -Dcom.amazonaws.sdk.disableEc2Metadata=true \
  -Dspring.profiles.active=${PROFILES} \
  -Dserver.env=${ENV} \
  -jar app.jar"]
```

**B를 권장하는 이유**: 힙 상한과 컨테이너 리밋은 항상 함께 움직여야 하는 값인데, 지금은 두 레포에 흩어져 있어
한쪽만 바뀌면 정확히 이번 같은 사고가 다시 납니다. B로 하면 ECS task definition 한 곳에서 두 값을 같이 관리할 수 있습니다.
**task definition에 `JAVA_OPTS`를 주입하는 인프라 쪽 작업은 groble-infra에서 처리합니다** — 백엔드는 Dockerfile만 봐주시면 됩니다.

> ⚠️ **B로 갈 때 주의 2가지**
> 1. **`exec`를 반드시 유지**해 주세요. 빠지면 `sh`가 PID 1이 되어 **SIGTERM이 JVM에 전달되지 않고**, graceful shutdown이 깨집니다.
>    (인프라 Phase 4의 rolling 배포 전환에도 graceful shutdown이 전제로 걸려 있습니다.)
> 2. `${PROFILES}` / `${ENV}`는 지금 exec 형식이라 셸이 확장하지 않고 **Spring의 프로퍼티 플레이스홀더 해석이 환경변수로 대신 풀어주고 있습니다.**
>    B의 `sh -c` 형식에서는 셸이 먼저 확장하게 되며 결과는 동일하지만, 이 부분을 건드릴 때는 **배포 후 실제 활성 프로파일을 반드시 확인**해 주세요.

### 4.3 `-Xmx900m` 근거

**핵심 근거 — GC 후 라이브 데이터 크기 (`jvm_gc_live_data_size_bytes`, 15일)**

| | prod | dev |
|---|---|---|
| p50 | 258 MiB | 169 MiB |
| p99 | 443 MiB | 304 MiB |
| **최대** | **510.5 MiB** | 304.6 MiB |

이 값이 **앱이 실제로 붙들고 있는 메모리**입니다 (major GC 직후의 old gen 크기 = 쓰레기가 걷힌 뒤의 라이브 셋).
2.2절의 heap used p99(1,362 MiB)와 비교하면 **실제 필요량의 약 2.7배가 부풀려져 보이고 있었습니다.**
G1이 상한을 2,878 MiB로 알고 있어 회수를 미룬 결과이며, 이 자체가 오설정의 증거입니다.

`-Xmx900m`은 피크 라이브 셋(510 MiB) 대비 **약 1.76배 여유**입니다.

**컨테이너 1,500 MiB 예산 배분**

| 항목 | 값 | 근거 |
|---|---|---|
| 컨테이너 하드리밋 | 1,500 MiB | 인프라가 정한 값 (변경 불필요) |
| − 힙 상한 (`-Xmx`) | 900 MiB | 라이브 셋 최대 510 MiB의 1.76배 |
| − nonheap committed | 400 MiB | 실측 (Metaspace·CodeCache·Compressed Class Space) |
| = 스레드 스택 / Direct Buffer / GC 내부 구조 / malloc 몫 | **약 200 MiB** | ⚠️ 넉넉하지 않음 |

> ⚠️ **`-Xms`를 `-Xmx`와 같게 두지 마십시오.** 위 표대로 예산이 빠듯해서, `-Xms900m`으로 힙을 처음부터
> 전부 커밋하면 상시 RSS가 1,400 MiB 안팎까지 올라가 여유가 거의 없어집니다.
> 라이브 셋이 510 MiB뿐이라 **힙이 900 MiB를 다 쓸 일은 실제로는 드뭅니다** — `-Xms512m`으로 두면
> 필요할 때만 커밋되어 평소 RSS가 낮게 유지됩니다. 상한(`-Xmx`)만 확실히 막으면 목적은 달성됩니다.

> ℹ️ **컨테이너 하드리밋(1,500 MiB)은 올릴 필요가 없습니다.** 따라서 이 건은 **백엔드 수정만으로 종결**되며,
> 인프라의 노드 사이징(Phase 7/8) 재검토로 번지지 않습니다.

### 4.4 함께 검토 부탁드리는 항목 (선택)

| 항목 | 이유 |
|---|---|
| `-XX:MaxMetaspaceSize` 설정 | 현재 Metaspace 상한이 **무제한**입니다. 누수가 나면 컨테이너를 통째로 밀어냅니다. 값은 현재 실측(비힙 커밋 합계 400 MiB)을 확인하신 뒤 정해주세요 |
| `-Xlog:gc*` (stdout) | 검증 기간 동안만이라도 켜주시면 GC 로그가 Loki로 수집되어, 힙 상한이 적절한지 판단할 수 있습니다 |

---

## 5. 확인 완료된 사항

작성 초안에서 "라이브 셋을 알 수 없어 `-Xmx` 값이 잠정적"이라고 남겼던 항목은 **측정으로 해소되었습니다.**

- `jvm_gc_live_data_size_bytes` 15일 최대값: **prod 510.5 MiB / dev 304.6 MiB** (4.3절)
- 판정 기준이었던 600 MiB를 밑돌므로 **`-Xmx900m`이 적정**하며, 컨테이너 리밋 상향은 필요 없습니다.

따라서 백엔드에서 별도로 확인하실 항목은 없습니다. 다만 배포 후 6절의 검증 항목은 확인 부탁드립니다.

---

## 6. 검증 (배포 후)

수정 이미지를 **dev에 먼저 배포**하고 확인한 뒤 prod로 진행해 주세요.

- [ ] `jvm_memory_max_bytes{id="G1 Old Gen"}` 이 **900 MiB 근처**로 내려왔는지 (2,878 MiB가 아님)
- [ ] 컨테이너 RSS가 **1,500 MiB에 붙어 있지 않은지** — 1,100~1,300 MiB 선에서 안정되는 것이 기대 동작\n- [ ] RSS가 **1,400 MiB를 넘어 계속 머문다면 `-Xmx`를 800m으로 낮춰**주세요 (4.3절 예산표의 여유가 200 MiB뿐입니다)
- [ ] 노드 스왑 사용량이 **의미 있게 줄었는지** (현재 최대 947 MiB)
- [ ] **GC 평균 pause가 463 ms에서 내려왔는지** — 개선 여부를 가장 잘 보여주는 지표
- [ ] OOM으로 인한 태스크 재시작이 없는지 (2~3일 관찰)
- [ ] 활성 Spring 프로파일이 의도대로인지 (4.2의 주의사항 2번)

인프라 쪽에서 위 지표를 함께 보고 있으니, 배포 시점만 알려주시면 관측 결과를 회신드리겠습니다.

---

## 7. 참고

| 문서 | 내용 |
|---|---|
| `groble-infra/docs/runbook/phase-02-observability.md` | 이 측정이 나온 Phase (2-0 API 태스크 워킹셋 측정) |
| `groble-infra/docs/runbook/phase-07-prod-asg.md` | 스왑이 사라지는 Phase |
| `groble-infra/docs/infra-ha-improvement-plan.md` §2.1 | 트래픽·자원 기준선 |
