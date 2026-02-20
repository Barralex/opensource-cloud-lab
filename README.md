# Open Source Cloud Lab

Cloud-agnostic infrastructure, 100% open source. Deployable on Digital Ocean, Hetzner or bare metal.

## Stack

- **IaC:** OpenTofu
- **Runtime:** k3s (lightweight Kubernetes)
- **GitOps:** Argo CD
- **Ingress:** NGINX + TLS 1.3
- **DB:** PostgreSQL 16
- **Storage:** MinIO (S3-compatible)
- **Monitoring:** Prometheus + Grafana
- **Secrets:** SOPS + Age

## Requirements

```bash
brew install doctl opentofu kubectl sops age
```

## Setup

```bash
# 1. Clone and configure
cp .env.example .env
# Edit .env with your DIGITALOCEAN_TOKEN

# 2. Authenticate DO CLI
source .env && doctl auth init -t $DIGITALOCEAN_TOKEN

# 3. Initialize and deploy
cd tofu
tofu init
tofu plan
tofu apply
```

## Structure

```
tofu/           # Infrastructure as Code
k3s/            # Kubernetes manifests
```

## Principles

- 100% Open Source
- Cloud Agnostic
- No vendor lock-in
- No hardcoded credentials
