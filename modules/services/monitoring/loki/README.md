# Loki Service Module

Loki is a log aggregation system designed to store and query logs from all your applications and infrastructure.

## Features

- **S3 Storage Backend**: Uses S3 for long-term log storage
- **Bridge Mode Deployment**: Optimized for EC2 instances
- **Service Discovery**: Integrated with AWS Service Discovery
- **Auto-scaling**: Configurable resource allocation
- **Cost Optimized**: Lifecycle policies for log retention

## Architecture

```
Spring API (other instances) → OpenTelemetry Collector → Loki (monitoring instance) → S3 Storage
                                                                ↓
                                                            Grafana (queries)
```

## Configuration

### Required Variables

- `ecs_cluster_id`: ECS cluster where Loki will be deployed
- `execution_role_arn`: ECS execution role with S3 permissions
- `task_role_arn`: ECS task role with S3 permissions
- `service_discovery_namespace_id`: Service discovery namespace
- `aws_region`: AWS region for S3 storage

### Optional Variables

- `loki_version`: Loki Docker image version (default: 3.0.0)
- `log_retention_days`: S3 log retention period (default: 30 days)
- `cpu/memory`: Resource allocation (default: 0.5 vCPU, 1GB RAM)

## Resource Requirements

Loki requires more resources than Grafana due to indexing and querying:
- **CPU**: 0.5 vCPU (512 units)
- **Memory**: 1GB (1024MB)
- **Storage**: S3 (no local storage needed)

## Endpoints

- **HTTP API**: Port 3100
- **Health Check**: `/ready`
- **Metrics**: `/metrics`

## S3 Storage

Loki uses S3 for:
- **Chunks**: Compressed log data
- **Index**: BoltDB index files
- **Rules**: Alert/recording rules

Lifecycle policy automatically deletes logs after retention period.

## Service Discovery

Loki is registered with AWS Service Discovery as `loki.<namespace>:3100` for internal communication.

## Deployment

Deploy to monitoring instances only using placement constraints:
```
attribute:environment == monitoring
```

## Integration

### With Grafana
Add Loki as a data source in Grafana:
```
URL: http://loki.<namespace>:3100
```

### With OpenTelemetry
Configure OpenTelemetry Collector to export logs:
```yaml
exporters:
  loki:
    endpoint: "http://loki.<namespace>:3100/loki/api/v1/push"
```
