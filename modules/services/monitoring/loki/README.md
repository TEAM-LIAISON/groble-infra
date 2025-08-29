# Loki Service Module

Loki is a log aggregation system designed to store and query logs from all your applications and infrastructure.

## Features

- **S3 Storage Backend**: Uses S3 for long-term log storage with versioning
- **Host Mode Deployment**: Direct localhost communication
- **OTLP Integration**: Native OTLP endpoint for OpenTelemetry Collector
- **TSDB Schema**: Uses v13 schema with TSDB shipper
- **Auto-scaling**: Configurable resource allocation
- **Cost Optimized**: S3 lifecycle policies for log retention

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
- **OTLP Endpoint**: Port 3100 (`/otlp`)
- **gRPC API**: Port 9096
- **Health Check**: `/ready`
- **Metrics**: `/metrics`

## S3 Storage

Loki uses S3 for:
- **Chunks**: Compressed log data
- **Index**: BoltDB index files
- **Rules**: Alert/recording rules

Lifecycle policy automatically deletes logs after retention period.

## Deployment

- **Host Mode**: Direct localhost communication (no service discovery)
- **Placement Constraint**: `attribute:environment == monitoring`
- **S3 Integration**: Automatic bucket creation with lifecycle policies

## Integration

### With Grafana
Add Loki as a data source in Grafana:
```
URL: http://localhost:3100
```

### With OpenTelemetry Collector
The collector exports logs via OTLP HTTP:
```yaml
exporters:
  otlphttp/loki:
    endpoint: "http://localhost:3100/otlp"
    headers:
      "Content-Type": "application/x-protobuf"
```
