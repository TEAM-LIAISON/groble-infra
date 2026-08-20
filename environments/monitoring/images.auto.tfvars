# 모니터링 스택 이미지 태그 — **버전 관리 대상**
#
# terraform.tfvars 는 .gitignore 의 `*.tfvars` 에 걸려 있다(시크릿 포함).
# 그 결과 "지금 어떤 이미지가 떠 있는지"가 git 이력에 남지 않아, 롤백하려면
# 이전 태그를 따로 기억해야 했다. 시크릿이 없는 이미지 식별자만 이 파일로 분리해
# 추적한다. `*.auto.tfvars` 는 terraform 이 자동으로 읽는다.
#
# ⚠️ 이미지 태그는 여기에만 둔다. terraform.tfvars 에 같은 변수를 다시 쓰지 말 것
#    (auto.tfvars 가 terraform.tfvars 보다 나중에 로드되어 조용히 덮어쓴다).
#
# Prometheus/Loki/otelcol 은 groble-images CI 가 config 를 구워 ECR 에 push 한 이미지다.
# 설정 변경은 이 리포지토리가 아니라 groble-images 에서 하고, 여기 태그를 올린다.
# 태그 규칙: <업스트림버전>-<config내용해시>

# Grafana — Docker Hub. 아직 config baking 대상이 아니다 (runbook Phase 2-2)
grafana_image   = "grafana/grafana"
grafana_version = "10.2.0"

# Loki — groble-images
monitoring_loki_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-loki:3.6.15-c8fcfa0"

# OpenTelemetry Collector — groble-images
monitoring_otelcol_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-otelcol:0.132.0-57015e3"

# Prometheus — groble-images
# 2026-08-20: v2.45.0-6cbe957 -> v2.45.0-3c2a266 (노드 타깃 ec2_sd_configs 전환, runbook Phase 2-1)
monitoring_prometheus_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-prometheus:v2.45.0-3c2a266"
