# Service Discovery Private DNS Namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "${var.project_name}.local"
  vpc  = var.vpc_id

  tags = {
    Name        = "${var.project_name}-service-discovery"
    Environment = "shared"
    Component   = "service-discovery"
  }
}
