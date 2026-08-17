terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # AWS Chatbot은 리전 서비스가 아니다 — API 엔드포인트가 us-east-2에만 존재한다.
      # (ap-northeast-2로 호출하면 "Could not connect to the endpoint URL"로 실패한다)
      # SNS 토픽·알람은 ap-northeast-2에 두고, Chatbot 설정만 이 별칭으로 만든다.
      configuration_aliases = [aws.chatbot]
    }
  }
}
