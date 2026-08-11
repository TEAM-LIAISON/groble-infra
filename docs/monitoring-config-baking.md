# 모니터링 Config Baking 로드맵

> 목표: 모니터링 컨테이너 설정을 "Terraform env-var + 셸 echo + 임시파일" 우회로에서
> **이미지에 구운 설정 파일 + 동적 값만 env 주입** 방식으로 전환한다.

---

## 0. 범위 (Scope)

현재 config 주입 방식을 서비스별로 분류한 결과, **작업 대상은 3개뿐**이다.

| 서비스 | 현재 방식 | Baking 대상? | 비고 |
|---|---|---|---|
| **prometheus** | env `PROMETHEUS_CONFIG_YAML` → 본 컨테이너가 `echo > /tmp/prometheus.yml` | ✅ 대상 | 치환값 전부 정적. 타겟 IP 하드코딩(별도 이슈) |
| **otelcol** | env `OTELCOL_CONFIG_YAML` → **init 컨테이너**가 `echo > /tmp` 공유볼륨 | ✅ 대상 | region만 동적, 나머지 정적 |
| **loki** | env `LOKI_CONFIG_YAML` → `echo > /etc/loki/loki-config.yaml` | ✅ 대상 | **S3 버킷명이 진짜 동적** (random suffix) |
| node-exporter | CLI 플래그만 사용 | ❌ 불필요 | config 파일 없음 |
| cadvisor | CLI 플래그만 사용 | ❌ 불필요 | config 파일 없음 |
| rds-exporter | CLI 플래그 + env(DSN) | ❌ 불필요 | config 파일 없음 |
| grafana | provisioning/env | ❌ 이번 범위 밖 | YAML echo 문제 없음 |

---

## 1. 목표 아키텍처 (Target)

```
[Config 소스코드]  docker/monitoring/<svc>/config.yaml   (git 관리, 단일 진실원)
        │  docker build (FROM 업스트림 + COPY config)
        ▼
[커스텀 이미지]    ECR: groble-monitoring/<svc>:<upstream>-<confighash>
        │  Terraform은 이 이미지 태그만 참조
        ▼
[ECS Task]        command = --config=/etc/<svc>/config.yaml   (한 줄)
                  동적 값만 environment[] 로 주입
```

**핵심 원칙**
1. 설정 파일은 **이미지 안 고정 경로**에 존재한다. task def는 `--config=<경로>` 한 줄.
2. Terraform은 설정 **내용**을 모른다. 이미지 **태그**와 **동적 값 몇 개**만 안다.
3. `local_file`, init 컨테이너, `echo > /tmp` — 전부 삭제.

---

## 2. 동적 값 경계 (가장 중요한 설계 결정)

"무엇을 굽고, 무엇을 런타임에 주입할지"를 서비스별로 확정한다.
각 도구의 **네이티브 env 확장 지원 여부**가 방식을 가른다.

### prometheus — 전부 baking (동적 값 없음)
- 치환값: `aws_region`, `scrape_interval`, `evaluation_interval` → 전부 상수.
- Prometheus는 config 내 일반 env 확장을 지원하지 않음 → **리터럴로 굽는다**
  (`ap-northeast-2`, `15s` 등).
- ⚠️ **별도 이슈**: 스크레이프 타겟 IP 하드코딩(`10.0.11.62` 등). 이대로 구우면
  인스턴스 교체 시 이미지 재빌드가 필요. → **팔로업으로 `ec2_sd_configs`(EC2 서비스
  디스커버리) 전환 권장.** 이번 baking 범위에서는 현행 IP를 그대로 굽되, 이슈로 남긴다.

### otelcol — region만 env, 나머지 baking
- OTel Collector는 **`${env:VAR}` 네이티브 확장 지원**.
- config에 `region: ${env:AWS_REGION}` 로 굽고, `AWS_REGION` env 주입.
- `collector_version`은 라벨용 → 리터럴로 굽거나 env. 리터럴 권장(이미지 태그와 일치).

### loki — S3 버킷명·region을 env (유일한 진짜 동적 케이스)
- Loki는 **`-config.expand-env=true`** 플래그로 `${VAR}` 런타임 확장 지원.
- config에 `bucketnames: ${S3_BUCKET}`, `region: ${AWS_REGION}` 로 굽고
  기동을 `loki -config.file=/etc/loki/config.yaml -config.expand-env=true` 로.
- Terraform은 `S3_BUCKET`(= `aws_s3_bucket.loki_storage.bucket`), `AWS_REGION` env만 주입.

> 요약: **동적 주입이 정말 필요한 값은 Loki의 S3 버킷명 하나뿐.** 나머지는 상수라
> 이미지에 구워도 안전하다. 각 도구의 네이티브 확장을 쓰므로 셸 echo가 사라진다.

---

## 3. 레포 & 이미지 구조 — 별도 이미지 레포로 분리

**결정**: 이미지 빌드 코드는 이 인프라 레포에 두지 않고 **별도 레포**로 분리한다.
이는 신규 패턴이 아니라, 이 레포가 이미 `spring_app_image`에 쓰는 방식과 동일하다
(이미지는 외부에서 빌드·푸시, 태그만 변수로 주입 / ECR 레지스트리는 Terraform 소유).

```
[신규 레포] groble-monitoring-images/
  prometheus/
    Dockerfile          # FROM prom/prometheus:v2.45.0 + COPY config
    prometheus.yml       # 구워질 설정 (단일 진실원)
  otelcol/
    Dockerfile
    otelcol-config.yaml
  loki/
    Dockerfile
    loki-config.yaml
  .github/workflows/build.yml   # 변경된 서비스만 build→검증→ECR push
```

- 모니터링 3개는 config+Dockerfile뿐이라 **레포 하나 + 서브디렉토리 3개 + 워크플로 하나**로 묶는다
  (서비스별 레포 분리는 과함). 앱 이미지는 앱 코드가 있으니 자기 레포 유지.
- 기존 `modules/services/monitoring/<svc>/config/*.yaml` 및 `rendered-*` → 신규 레포로 이전 후 이 레포에선 삭제.

### 책임 경계

| | 이미지 레포 (신규) | 인프라 레포 (여기) |
|---|---|---|
| 소유 | Dockerfile, config YAML, GitHub Actions | **ECR 레지스트리 리소스**, ECS task def |
| 동작 | build → 문법검증 → ECR push | 이미지 **태그를 변수로 받아** 배포 |

- **ECR 레포**: 레지스트리 리소스는 계속 Terraform(`platform/ecr`)이 소유. monitoring용 레포 3개 추가
  (`spring_app_api` repo들과 동일하게 `create_*` 플래그 게이팅).
- **태그 전략**: `<업스트림버전>-<config내용 해시>` 예) `v2.45.0-a1b2c3d`.
  - 설정이 바뀌면 태그가 바뀜 → task def 갱신 → **깨끗한 롤백**(이전 태그로 되돌림).

---

## 4. 빌드 파이프라인 & Handoff

- **빌드**: 신규 레포의 GitHub Actions — 변경된 서비스만 `docker build` → ECR push.
- **문법 검증(빌드 게이트)**: promtool check config / `otelcol validate` / `loki -verify-config`.
  → "깨진 config가 이미지에 구워지는" 사고를 빌드 단계에서 차단.
- **Handoff = tfvars 변수** (`spring_app_image`와 동일 방식, SSM 미도입):
  - 인프라 레포에 `monitoring_prometheus_image`, `..._otelcol_image`, `..._loki_image` 변수 추가
    (`repo:tag` 형식 검증 포함, `spring_app_image`처럼).
  - 이미지 레포 CI가 새 태그를 산출 → 인프라 레포 tfvars 갱신(수동 PR 또는 CI dispatch) → `apply`.
  - 장점: "지금 어떤 config가 떠 있나"가 인프라 레포 git에 감사 가능하게 남고, 기존 패턴과 일관.

---

## 5. Terraform 변경 (서비스별 공통 패턴)

제거:
- `templatefile(...)` 로 YAML 통째 렌더링하는 `locals`
- `local_file.*_config` (rendered 파일 쓰기)
- `environment` 의 `*_CONFIG_YAML` 항목
- otelcol의 `otelcol-init` 컨테이너 + `tmp-volume`(host `/tmp`)
- prometheus/loki 본 컨테이너의 `echo ... > file &&` entrypoint

추가/변경:
- `image = "<ECR>/<svc>:<tag>"` (var로 태그 주입)
- `command = ["--config=/etc/<svc>/config.yaml", ...]` (필요 플래그 유지)
- `environment` 에 **동적 값만** (loki: `S3_BUCKET`,`AWS_REGION` / otelcol: `AWS_REGION`)

---

## 6. 롤아웃 순서 (안전 우선)

가장 단순하고 리스크 낮은 것부터. Loki는 과거 credential/S3 이슈 이력이 있어 마지막.

1. **otelcol** — 가장 깔끔. init 컨테이너+공유볼륨까지 통째로 제거되어 효과가 큼. 상태 없음(stateless).
2. **prometheus** — 단일 컨테이너. baking 후 `--config` 한 줄. 타겟 IP 이슈는 별도 티켓.
3. **loki** — 동적 값(S3 버킷) + `-config.expand-env` 검증 필요. S3 적재까지 확인.

각 단계는 **독립 배포·독립 검증·독립 롤백** 가능하게 서비스 단위로 커밋한다.

---

## 7. 검증 (서비스별 완료 기준)

- **공통**: 새 task 기동 → `describe-task-definition`에 `*_CONFIG_YAML` env 없음 확인 →
  컨테이너 안 `cat /etc/<svc>/config.yaml` 로 구워진 config 확인.
- **prometheus**: `/-/healthy` 200, 타겟들 `up` 상태, `/-/reload` 동작.
- **otelcol**: 파이프라인 기동 로그, region 확장 확인, Prometheus/Loki로 전달 확인.
- **loki**: `${S3_BUCKET}` 확장 확인, **S3에 청크 적재** 확인(과거 버그 재발 방지),
  Grafana에서 로그 조회.

## 8. 리스크 & 롤백

- 리스크: config 해시 태그 관리 누락 시 이미지/태그 불일치 → CI 또는 스크립트로 태그 자동화.
- 롤백: task def를 **이전 이미지 태그**로 되돌리면 끝(설정이 이미지에 있으므로 원자적).
- Loki `-config.expand-env` 누락 시 `${S3_BUCKET}`가 리터럴로 들어감 → 기동 검증에서 잡는다.

---

## 부록: 관련 팔로업 이슈 (이번 범위 밖, 기록만)
- Prometheus 스크레이프 타겟 IP 하드코딩 → `ec2_sd_configs` 전환
- API task `DB_PASSWORD` 평문 → SSM `valueFrom`
- ECS-optimized AMI 전환 (user_data 축소, Loki credential proxy 버그 원천 차단)
