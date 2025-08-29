# Prometheus Service Module

Prometheus is a monitoring system and time series database designed for reliability and scalability.

## Features

- **TSDB Storage**: Local time series database with configurable retention
- **S3 Integration**: Dedicated S3 bucket with encryption and versioning
- **Host Mode Deployment**: Direct localhost communication
- **Init Container**: Dynamic configuration generation using Terraform templates
- **Auto-scaling**: Configurable resource allocation
- **Web UI**: Built-in web interface for queries and configuration

## Architecture

```
Spring API (Prod/Dev) → OpenTelemetry Collector → Prometheus (monitoring instance)
                                                      ↓
Grafana ← Prometheus ← Local TSDB ← S3 Storage (Backup)
```

## Current Integrations

### Active Scrape Targets
- **Prometheus Self**: `localhost:9090/metrics`
- **OpenTelemetry Collector Internal**: `localhost:8888/metrics`
- **OpenTelemetry Collector Exported**: `localhost:8889/metrics`
- **Loki**: `localhost:3100/metrics`
- **Grafana**: `localhost:3000/metrics`

### Future Integrations
- **Spring Boot Apps**: Direct scraping via `/actuator/prometheus`
- **AWS CloudWatch**: CloudWatch metrics integration
- **Remote Storage**: Long-term storage in AWS Managed Prometheus

## Configuration

### Required Variables

- `ecs_cluster_id`: ECS cluster where Prometheus will be deployed
- `execution_role_arn`: ECS execution role with S3 permissions
- `task_role_arn`: ECS task role with S3 permissions
- `service_discovery_namespace_id`: Service discovery namespace

### Optional Variables

- `prometheus_version`: Prometheus version (default: v2.45.0)
- `scrape_interval`: Global scrape interval (default: 15s)
- `evaluation_interval`: Rule evaluation interval (default: 30s)
- `local_retention_time`: Local storage retention (default: 15d)
- `metrics_retention_days`: S3 retention period (default: 90 days)

## Resource Requirements

Prometheus requires moderate resources for metrics storage and processing:
- **CPU**: 0.5 vCPU (512 units)
- **Memory**: 1GB (1024MB) 
- **Storage**: Local + S3 backup

## Endpoints

- **Web UI**: Port 9090 (`/`)
- **API**: Port 9090 (`/api/v1/`)
- **Health Check**: `/health`, `/-/healthy`
- **Metrics**: `/metrics`
- **Configuration**: `/-/config`

## Data Retention Strategy

### Local Storage (Fast Access)
- **Retention**: 15 days by default
- **Size Limit**: 10GB by default
- **Purpose**: Recent metrics for alerting and dashboards

### S3 Storage (Long-term)
- **Retention**: 90 days by default
- **Purpose**: Historical analysis and compliance
- **Cost**: Optimized with lifecycle policies

## Deployment

- **Host Mode**: Direct localhost communication (no service discovery)
- **Placement Constraint**: `attribute:environment == monitoring`
- **S3 Storage**: Automatic S3 bucket with versioning and encryption
- **Init Container**: Runtime configuration generation from Terraform templates

## Integration with Existing Stack

### With Grafana
Add Prometheus as a data source in Grafana:
```
URL: http://localhost:9090
Type: Prometheus
```

### With OpenTelemetry Collector
The collector already exposes metrics on port 8888 that Prometheus scrapes.

### With Spring Applications
Update your Spring applications to include:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    prometheus:
      enabled: true
```

## Usage

```hcl
module "prometheus" {
  source = "../../modules/services/monitoring/prometheus"

  environment                     = "monitoring"
  ecs_cluster_id                 = var.ecs_cluster_id
  execution_role_arn             = var.execution_role_arn
  task_role_arn                  = var.task_role_arn
  service_discovery_namespace_id = var.service_discovery_namespace_id
  
  prometheus_domain              = "prometheus.example.com"
  target_group_arn               = aws_lb_target_group.prometheus.arn
  alb_listener                   = aws_lb_listener_rule.prometheus
  
  cpu                           = 512
  memory                        = 1024
  desired_count                 = 1
  
  scrape_interval               = "15s"
  local_retention_time          = "15d"
  metrics_retention_days        = 90
  
  aws_region                    = "ap-northeast-2"
}
```

## Monitoring Queries

### Common PromQL Queries
```promql
# Container resource usage
container_memory_usage_bytes{container="prometheus"}

# Scrape duration
prometheus_target_scrape_duration_seconds

# OpenTelemetry Collector metrics
otelcol_processor_batch_send_size_sum

# Spring application metrics (future)
http_server_requests_seconds_count{application="groble-api"}
```

## Alerting (Future Enhancement)

### Planned Alerts
- High memory usage
- Scrape target failures
- High query latency
- Storage capacity warnings

## Security

- No authentication required for internal access
- External access via ALB with optional authentication
- S3 storage encrypted at rest
- IAM roles for AWS service access

## Backup and Recovery

- **Configuration**: Stored in version control
- **Data**: Local TSDB + S3 backup
- **Restoration**: Redeploy service, data recovery from S3

## Future Enhancements

- [ ] Alertmanager integration
- [ ] Recording rules for complex queries  
- [ ] AWS Managed Prometheus remote write
- [ ] Federation with multiple Prometheus instances
- [ ] Advanced service discovery (ECS, Consul)
- [ ] Thanos for long-term storage and HA