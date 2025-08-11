#!/bin/bash

# Groble Infrastructure 단계적 배포 스크립트
# 사용법: ./deploy-step.sh [step_number] [action]
# 예시: ./deploy-step.sh 1 plan
#       ./deploy-step.sh 1 apply
#       ./deploy-step.sh 1 destroy

set -e

STEP=$1
ACTION=${2:-plan}

if [ -z "$STEP" ]; then
    echo "사용법: $0 <step_number> [action]"
    echo "단계:"
    echo "  1: VPC 및 네트워크 인프라"
    echo "  2: 보안 그룹"
    echo "  3: 로드 밸런서"
    echo "  4: EC2 인스턴스"
    echo ""
    echo "액션: plan, apply, destroy, show"
    exit 1
fi

# 파일 목록
declare -a FILES=(
    "01-vpc.tf"
    "02-security-groups.tf" 
    "03-load-balancer.tf"
    "04-ec2-instances.tf"
)

echo "=== Groble Infrastructure 단계적 배포 ==="
echo "단계 $STEP 까지 배포 중..."

# 현재 단계까지의 파일들을 활성화
for i in $(seq 0 $((STEP-1))); do
    if [ $i -lt ${#FILES[@]} ]; then
        file=${FILES[$i]}
        if [ -f "${file}.disabled" ]; then
            echo "활성화: $file"
            mv "${file}.disabled" "$file"
        fi
    fi
done

# 현재 단계 이후의 파일들을 비활성화
for i in $(seq $STEP $((${#FILES[@]}-1))); do
    file=${FILES[$i]}
    if [ -f "$file" ]; then
        echo "비활성화: $file"
        mv "$file" "${file}.disabled"
    fi
done

echo ""
echo "활성화된 파일들:"
ls -la *.tf 2>/dev/null || echo "활성화된 .tf 파일이 없습니다."

echo ""
echo "=== Terraform $ACTION 실행 ==="

case $ACTION in
    plan)
        terraform plan
        ;;
    apply)
        terraform apply
        ;;
    destroy)
        terraform destroy
        ;;
    show)
        terraform show
        ;;
    *)
        echo "지원하지 않는 액션: $ACTION"
        echo "사용 가능한 액션: plan, apply, destroy, show"
        exit 1
        ;;
esac

echo ""
echo "=== 단계 $STEP $ACTION 완료 ==="
