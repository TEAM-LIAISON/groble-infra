#!/bin/bash
set -euxo pipefail
#############################################################################
# 모니터링 노드 부트스트랩 — ECS-optimized Amazon Linux 2023
#
# Phase 4(모니터링 노드 재구축)의 신 노드용이다. 구 노드의
# monitoring_user_data.sh(Ubuntu)를 대체하며, 그 스크립트가 하던 일 중
# **관측 스택 실행에 필요한 것만** 남겼다.
#
# 이 노드는 NAT 도 bastion 도 VPN 도 아니다. 그 세 역할은 구 노드에 남아 있고,
# 폐기는 Phase 3(NAT) → Phase 9(접근 경로) → Phase 11(정리) 의 몫이다.
#
# ── 구 스크립트에서 뺀 것과 그 이유 ──────────────────────────────────────
#
#  1. Docker 설치 · ECS 에이전트 `docker run`
#     → ECS-optimized AMI 에 이미 있고 ecs-init 이 systemd(ecs.service)로 관리한다.
#       구 노드는 에이전트를 amazon/amazon-ecs-agent:latest 로 **버전 고정 없이**
#       띄우고 있었다. 이제 AMI 가 버전을 고정한다.
#
#  2. task IAM role credential 프록시 iptables (169.254.170.2 → 127.0.0.1:51679)
#     → **ecs-init 이 설치하고 재부팅에도 유지한다.** 구 노드는 이 규칙을
#       user_data 에서 수동으로 넣고 iptables-persistent 로도 저장하지 않아,
#       재부팅하면 태스크 IAM 롤이 조용히 깨졌다 — 과거 Loki S3 적재 실패의
#       원인이 이것이다. AL2023 전환의 가장 큰 실익이다.
#
#  3. NAT (ip_forward · MASQUERADE · FORWARD) 와 bastion SSH iptables
#     → 이 노드의 역할이 아니다. private 서브넷의 기본 경로는 여전히 구 노드를
#       가리키며, 이 노드 자신의 아웃바운드도 그 경로를 탄다.
#
#  4. iptables-persistent · test-nat.sh · apt 패키지 설치
#     → 3번이 없어졌거나 apt 전용이다.
#############################################################################

#############################################################################
# 1. ECS 에이전트 설정
#############################################################################
# ECS-optimized AMI 는 부팅 시 ecs.service 가 이 파일을 읽는다.
# cloud-init 이 ecs.service 보다 먼저 실행되므로 여기서 쓰면 첫 기동부터 반영된다.

mkdir -p /etc/ecs

cat > /etc/ecs/ecs.config <<'ECS_CONFIG'
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_ENABLE_EXECUTION_ROLE_LOG_DRIVER=true
ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]
ECS_LOGLEVEL=info
ECS_CONTAINER_STOP_TIMEOUT=30s
ECS_CONFIG

# 클러스터명은 Terraform 이 채운다
echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config

# ⚠️ 이 attribute 가 없으면 모니터링 서비스 7개가 이 노드에 배치되지 않는다.
#    전부 `placement_constraints { expression = "attribute:environment == monitoring" }`
#    를 걸고 있다 (modules/services/monitoring/*/main.tf).
#    구 노드와 값이 같아야 병존 중 드레이닝으로 태스크를 밀어낼 수 있다.
echo 'ECS_INSTANCE_ATTRIBUTES={"environment":"monitoring","role":"monitor-server"}' >> /etc/ecs/ecs.config

# ⚠️ ECS_RESERVED_MEMORY — 계획서 §2.1 의 512 를 여기에 쓰면 안 된다.
#
#    512 는 t3.medium API 노드용 값이다. 이 노드는 t3.small 이고 관측 스택이
#    이미 꽉 차 있다:
#
#      태스크 레벨 memory 합계  = 1,792 MiB
#        (grafana 256 · prometheus 512 · loki 256 · otelcol 256 ·
#         node-exporter 128 · cadvisor 256 · rds-exporter 128)
#      구 노드가 ECS 에 등록한 메모리 = 1,910 MiB (남은 용량 118 MiB)
#      → 리눅스 가용 ≈ 1,910 + 64(현재 reserved) = 약 1,974 MiB
#
#    reserved 를 512 로 두면 등록량이 1,462 MiB 로 떨어져 **스택이 배치되지
#    않는다.** 128 이면 1,846 MiB 로 1,792 를 담고 54 MiB 가 남는다.
#
#    ⚠️ 즉 이 노드는 원래 과다 예약 상태이며, 정직한 값(256 이상)을 쓰면
#       스택이 안 뜬다. 여유를 늘리려면 아래 중 하나를 별도로 결정해야 한다:
#         - cadvisor 256 → 160, rds-exporter 128 → 96 으로 태스크 memory 조이기
#         - 노드를 t3.medium 으로 (월 ~$15 추가, 계획서 §2.1 의 "t3.small pet" 수정)
#    구 노드는 NAT·bastion·VPN 까지 겸직하면서 이 값으로 버티고 있었으므로,
#    그 셋이 빠지는 이 노드는 같은 값에서 실질 여유가 더 크다.
echo "ECS_RESERVED_MEMORY=128" >> /etc/ecs/ecs.config

#############################################################################
# 2. 호스트 볼륨 디렉터리
#############################################################################
# ⚠️ 이걸 빠뜨리면 Grafana 와 Prometheus 가 기동 즉시 죽는다.
#    두 태스크는 host 볼륨을 bind mount 하는데, 디렉터리가 없으면 Docker 가
#    root:root 0755 로 만들어 버린다. 컨테이너는 비루트로 실행되므로 쓰기가 막힌다:
#      grafana    user = 472:472    → /opt/grafana/data
#      prometheus user = 65534:65534 → /opt/prometheus/data
#    (loki 는 host 볼륨이 없다 — 청크가 S3 에 있다)
#
#    빈 디렉터리로 시작하는 것이 정상이다. 이 Phase 는 Prometheus 로컬 15일치
#    유실을 수용하고, Grafana 는 이미지의 provisioning 으로 복원된다
#    (대시보드·데이터소스·알림 규칙). 사용자 계정·silence·UI 로 만든 대시보드는
#    복원되지 않는다.

install -d -m 0755 -o 472   -g 472   /opt/grafana/data
install -d -m 0755 -o 65534 -g 65534 /opt/prometheus/data

#############################################################################
# 3. 에이전트 기동
#############################################################################
# AMI 기본값으로도 enable 되어 있으나, 설정을 쓴 뒤 명시적으로 보장한다.
systemctl enable --now ecs

#############################################################################
# 4. 부트스트랩 결과 기록
#############################################################################
# SSM 으로 들어왔을 때 이 노드가 무엇인지 바로 알 수 있게 남긴다.
cat > /etc/groble-node-info <<INFO
role=monitoring (observability stack only)
not=NAT, not=bastion, not=WireGuard   # 구 노드에 남아 있다
phase=4 (monitoring node rebuild)
ami=ECS-optimized Amazon Linux 2023
ecs_cluster=${cluster_name}
ecs_attributes=environment:monitoring
host_volumes=/opt/grafana/data(472) /opt/prometheus/data(65534)
INFO

echo "monitoring node bootstrap complete" | systemd-cat -t groble-bootstrap
