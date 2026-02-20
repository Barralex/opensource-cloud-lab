# CLAUDE.md - Open Source Cloud Lab

## Important

- **Always update `infra-status.html` when infrastructure changes** (pods, services, scaling, etc.)
- All code and comments must be in English

## Permissions

- Create and modify files in this directory
- Run OpenTofu, doctl, kubectl commands
- Install dependencies with brew
- Load environment variables from .env

## Context

Cloud-agnostic infrastructure for Elixir/Ash applications.
Cloud: Digital Ocean (also portable to Hetzner/bare metal).

## Current Infrastructure

```
🌐 Internet
     ↓
🖥️ Droplet: 104.248.237.80 (2vCPU/4GB)
     ↓
  ☸️ K3s v1.34.4
     ↓
  NGINX Ingress (:80/:443)
     ↓
  ┌─────────────────────────────────────┐
  │     Stress Lab x2 pods (:4000)      │
  │  /cpu /db /memory /upload /download │
  │  /diagram /health /metrics          │
  └─────────────────────────────────────┘
     ↓
  ┌────────────┐  ┌────────────┐  ┌────────────┐
  │ PostgreSQL │  │   MinIO    │  │  Argo CD   │
  │   :5432    │  │   :9000    │  │  /argocd   │
  └────────────┘  └────────────┘  └────────────┘
     ↓
  ┌────────────┐  ┌────────────┐  ┌────────────┐
  │ Prometheus │  │  Grafana   │  │pg_exporter │
  │   :9090    │  │  /grafana  │  │   :9187    │
  └────────────┘  └────────────┘  └────────────┘
```

## URLs

- App: http://104.248.237.80/
- Diagram: http://104.248.237.80/diagram
- Grafana: http://104.248.237.80/grafana/ (admin / admin123)
- Argo CD: http://104.248.237.80:30080 (admin / YNQt9-dw0pzWbJAl)
- SSH: `ssh -i ~/.ssh/id_ed25519_oss_cloud_lab root@104.248.237.80`

## API Endpoints

```bash
# Status
curl http://104.248.237.80/
curl http://104.248.237.80/health
curl http://104.248.237.80/metrics
curl http://104.248.237.80/diagram

# Load tests
curl http://104.248.237.80/cpu/500
curl http://104.248.237.80/db/10
curl http://104.248.237.80/memory/50

# S3/MinIO
curl -X POST http://104.248.237.80/upload/file.txt -H "Content-Type: application/octet-stream" -d "content"
curl http://104.248.237.80/download/file.txt
curl http://104.248.237.80/files
```

## Stack

| Layer | Tool |
|-------|------|
| IaC | OpenTofu |
| Runtime | K3s + Ubuntu 24.04 |
| GitOps | Argo CD |
| Ingress | NGINX Ingress |
| DB | PostgreSQL 16 |
| Storage | MinIO |
| Monitoring | Prometheus + Grafana + postgres_exporter |
| Network | DigitalOcean VPC |

## Scripts

```bash
# Full install: tofu + all services + app
./scripts/install-dev.sh

# Redeploy app only (fast)
./scripts/deploy-app.sh

# Destroy everything
./scripts/destroy-dev.sh
```

## Commands

```bash
# OpenTofu
cd tofu && tofu init && tofu plan && tofu apply

# Digital Ocean
doctl compute droplet list

# K3s (on server)
kubectl get nodes
kubectl get pods -A
```

## Constraints

- NO vendor lock-in (no AWS CDK, Azure Blueprints)
- NO hardcoded credentials
- All code and comments in English
