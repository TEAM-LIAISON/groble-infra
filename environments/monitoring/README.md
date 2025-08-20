# Monitoring Environment

This directory contains Terraform configuration for the monitoring environment, deploying Grafana and Loki services.

## Overview

- **Environment**: monitoring
- **Services**: Grafana, Loki
- **Deployment**: ECS on EC2 with Bridge Mode
- **Storage**: S3 for Loki log storage
- **Service Discovery**: AWS Service Discovery for internal communication

## Architecture

```
Spring API (other instances) → OpenTelemetry Collector → Loki (monitoring instance) → S3 Storage
                                                                ↓
                                                            Grafana (queries)
```

## Prerequisites

1. Shared environment must be deployed first
2. Monitoring EC2 instance should be tagged with `attribute:environment == monitoring`
3. Domain name for Grafana access
4. Service Discovery namespace created in shared environment

## Services Deployed

### Loki
- **Purpose**: Log aggregation and storage
- **Resources**: 0.5 vCPU, 1GB memory
- **Storage**: S3 backend with 30-day retention
- **Port**: 3100 (internal)
- **Endpoint**: `http://loki.groble.local:3100`

### Grafana
- **Purpose**: Visualization and dashboards
- **Resources**: 0.25 vCPU, 256MB memory
- **Port**: 3000 (ALB connected)
- **Access**: `https://monitor.groble.im`

## Configuration

### terraform.tfvars

Update the following variables in `terraform.tfvars`:

```hcl
# Grafana 설정
grafana_domain         = "your-grafana-domain.com"
grafana_admin_password = "your-secure-password"

# Loki 설정
loki_log_retention_days = 30
loki_cpu               = 512
loki_memory            = 1024
```

### Deployment

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Access

After deployment:
- **Grafana**: `https://your-grafana-domain.com`
  - Username: `admin`
  - Password: `your-configured-password`
- **Loki**: Internal only via service discovery

## Resources Created

### Loki Resources
- S3 bucket for log storage
- ECS Service for Loki
- ECS Task Definition (Bridge Mode)
- Service Discovery registration
- Lifecycle policies for cost optimization

### Grafana Resources
- ECS Service for Grafana
- ECS Task Definition (Bridge Mode)
- ALB Target Group integration
- ALB Listener Rule

## Integration

### Grafana Data Sources
After deployment, configure Grafana data sources:
1. **Loki**: `http://loki.groble.local:3100`
2. **Prometheus**: `http://otelcol.groble.local:8889` (when OpenTelemetry is added)

### Service Discovery
Services communicate via AWS Service Discovery:
- **Namespace**: `groble.local`
- **Loki**: `loki.groble.local:3100`
- **Grafana**: `grafana.groble.local:3000`

## Cost Optimization

- **S3 Lifecycle**: Automatic log deletion after retention period
- **No CloudWatch logs**: Uses local logging
- **No EBS volumes**: Ephemeral storage
- **Resource limits**: Minimal CPU/memory allocation
- **Placement constraints**: Deploy only to monitoring instance

## Monitoring

Both services are deployed only on EC2 instances with the `environment == monitoring` attribute for cost efficiency and resource isolation.

## Next Steps

1. Deploy OpenTelemetry Collector
2. Configure Spring applications to send logs to OpenTelemetry
3. Set up Grafana dashboards for log visualization
4. Configure alerting rules in Grafana
