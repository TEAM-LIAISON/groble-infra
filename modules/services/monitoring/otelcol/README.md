# OpenTelemetry Collector Module

OpenTelemetry Collector service for centralized telemetry data collection and processing.

## Features

- **OTLP Receivers**: HTTP (4318) and gRPC (4317) endpoints
- **Service Discovery**: Registered as `otelcol.groble.local`
- **Loki Integration**: Direct log export to Loki service
- **Future Ready**: Prometheus metrics export capability
- **Bridge Mode**: Optimized for EC2 instances

## Architecture

```
Spring API (Prod/Dev) → OTLP → OpenTelemetry Collector → Loki (Monitoring)
                                        ↓
                                  (Future: Prometheus)
```

## Current Data Flow

1. **Log Collection**: Spring Apps → OTLP → Collector → Loki
2. **Future Metrics**: Spring Apps → OTLP → Collector → Prometheus

## Configuration

### Required Variables

- `ecs_cluster_id`: ECS cluster for deployment
- `execution_role_arn`: ECS execution role
- `task_role_arn`: ECS task role
- `service_discovery_namespace_id`: Service discovery namespace
- `loki_endpoint`: Loki service endpoint (default: loki.groble.local:3100)

### Optional Variables

- `otelcol_image`: OpenTelemetry Collector image (default: otel/opentelemetry-collector-contrib)
- `otelcol_version`: Collector version (default: latest)
- `cpu/memory`: Resource allocation (default: 0.25 vCPU, 512MB)

## Endpoints

- **OTLP HTTP**: Port 4318 (`/v1/traces`, `/v1/metrics`, `/v1/logs`)
- **OTLP gRPC**: Port 4317
- **Health Check**: Port 13133 (`/`)
- **Metrics**: Port 8888 (`/metrics`)

## Service Discovery

Registered as `otelcol.groble.local:4318` for internal communication.

## Deployment

Deploys only to monitoring instances using placement constraints:
```
attribute:environment == monitoring
```

## Spring Application Integration

Update your Spring application configuration:

```yaml
# Before
otel:
  exporter:
    otlp:
      endpoint: http://localhost:4318

# After  
otel:
  exporter:
    otlp:
      endpoint: http://otelcol.groble.local:4318

logs:
  export:
    endpoint: http://otelcol.groble.local:4318/v1/logs
```

## Usage

```hcl
module "otelcol" {
  source = "../../modules/services/monitoring/otelcol"

  environment                     = "monitoring"
  ecs_cluster_id                 = var.ecs_cluster_id
  execution_role_arn             = var.execution_role_arn
  task_role_arn                  = var.task_role_arn
  service_discovery_namespace_id = var.service_discovery_namespace_id
  
  loki_endpoint                  = "http://loki.groble.local:3100"
  
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
