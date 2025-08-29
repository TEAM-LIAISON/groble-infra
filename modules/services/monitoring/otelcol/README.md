# OpenTelemetry Collector Module

OpenTelemetry Collector service for centralized telemetry data collection and processing.

## Features

- **OTLP Receivers**: HTTP (4318) and gRPC (4317) endpoints
- **Host Networking**: Direct localhost communication with monitoring stack
- **Init Container**: Dynamic configuration generation using Terraform templates
- **Loki Integration**: OTLP HTTP export to Loki service
- **Prometheus Metrics**: Active metrics export to Prometheus
- **Memory Management**: Built-in memory limiter and batch processing

## Architecture

```
Spring API (Prod/Dev) → OTLP → OpenTelemetry Collector → Loki (Monitoring)
                                        ↓
                                    Prometheus (Monitoring)
```

## Current Data Flow

1. **Log Collection**: Spring Apps → OTLP → Collector → Loki (via OTLP HTTP)
2. **Metrics Collection**: Spring Apps → OTLP → Collector → Prometheus (via metrics endpoint)
3. **Internal Metrics**: Collector self-monitoring → Prometheus

## Configuration

### Required Variables

- `ecs_cluster_id`: ECS cluster for deployment
- `execution_role_arn`: ECS execution role
- `task_role_arn`: ECS task role
- `service_discovery_namespace_id`: Service discovery namespace
- `aws_region`: AWS region for resource metadata

### Optional Variables

- `otelcol_image`: OpenTelemetry Collector image (default: otel/opentelemetry-collector-contrib)
- `otelcol_version`: Collector version (default: latest)
- `cpu/memory`: Resource allocation (default: 0.25 vCPU, 512MB)

## Endpoints

- **OTLP HTTP**: Port 4318 (`/v1/traces`, `/v1/metrics`, `/v1/logs`)
- **OTLP gRPC**: Port 4317
- **Health Check**: Port 13133 (`/`)
- **Internal Metrics**: Port 8888 (`/metrics`)
- **Prometheus Metrics**: Port 8889 (`/metrics`)

## Networking Mode

Uses **host networking** mode for direct localhost communication with other monitoring services:
- Loki: `localhost:3100`
- Prometheus: `localhost:9090`

## Deployment

- **Host Mode**: Direct communication without service discovery
- **Placement Constraint**: `attribute:environment == monitoring`
- **Init Container**: Generates configuration file at runtime

## Spring Application Integration

Update your Spring application configuration:

```yaml
# Spring Boot application configuration
management:
  otlp:
    tracing:
      endpoint: "http://monitoring-host:4318/v1/traces"
    metrics:
      export:
        endpoint: "http://monitoring-host:4318/v1/metrics"
  logging:
    otlp:
      endpoint: "http://monitoring-host:4318/v1/logs"
```

Note: Replace `monitoring-host` with the actual IP/hostname of your monitoring instance.

## Usage

```hcl
module "otelcol" {
  source = "../../modules/services/monitoring/otelcol"

  environment                     = "monitoring"
  ecs_cluster_id                 = var.ecs_cluster_id
  execution_role_arn             = var.execution_role_arn
  task_role_arn                  = var.task_role_arn
  service_discovery_namespace_id = var.service_discovery_namespace_id
  
  cpu                           = 256
  memory                        = 512
  desired_count                 = 1
  
  aws_region                    = "ap-northeast-2"
}
```

## Future Enhancements

- [ ] Prometheus metrics export
- [ ] Jaeger tracing (optional)
- [ ] Advanced processors (sampling, filtering)
- [ ] Multiple Loki endpoints
- [ ] Alerting rules
