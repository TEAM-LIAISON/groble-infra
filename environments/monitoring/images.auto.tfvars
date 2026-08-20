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

# Grafana — groble-images (대시보드·데이터소스·알림 프로비저닝 baked)
# 2026-08-20: grafana/grafana:10.2.0 -> ECR 11.6.3-b75b8fe (runbook Phase 2-2)
#   11.x 로 올린 이유는 네이티브 AWS SNS contact point 다. 10.2 에는 없어서
#   Slack Webhook 을 새로 발급해야 했다(= 시크릿이 하나 는다).
#   ⚠️ 10.2 로의 롤백은 불가능하다 — Grafana 11 이 SQLite 스키마를 단방향 마이그레이션한다.
grafana_image   = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-grafana"
grafana_version = "11.6.3-05735cc" # groble-images#6: 결제 실패 알람 2건 추가

# Loki — groble-images
monitoring_loki_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-loki:3.6.15-c8fcfa0"

# OpenTelemetry Collector — groble-images
monitoring_otelcol_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-otelcol:0.132.0-57015e3"

# Prometheus — groble-images
# 2026-08-20: v2.45.0-6cbe957 -> v2.45.0-3c2a266 (노드 타깃 ec2_sd_configs 전환, runbook Phase 2-1)
# 2026-08-20: v2.45.0-3c2a266 -> v2.45.0-12246df (대시보드용 recording rules 추가, runbook Phase 2-2)
# 2026-08-20: v2.45.0-12246df -> v2.45.0-143413d (recording rule 분모 clamp_min -> `> 0` 필터, groble-images#5)
#   리밋이 없는 컨테이너(ecs-agent 등)에서 수십억 % 가 나오던 버그 수정
#   ⚠️ Grafana 대시보드와 알림 규칙이 groble:* recording rule 에 의존한다.
#      이 이미지를 배포하지 않으면 해당 패널이 비고 알림은 NoData 가 된다.
monitoring_prometheus_image = "538827147369.dkr.ecr.ap-northeast-2.amazonaws.com/groble-prometheus:v2.45.0-143413d"
