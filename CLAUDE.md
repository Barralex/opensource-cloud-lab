# CLAUDE.md - Open Source Cloud Lab

## Important

- **Always update `stress-lab/infra-status.html` when infrastructure changes**
- **Local and Production must stay in sync** - same services, same manifests
- All code and comments must be in English

## Permissions

- Create and modify files in this directory
- Run OpenTofu, doctl, kubectl, k3d commands
- Install dependencies with brew
- Load environment variables from .env

## Context

Cloud-agnostic infrastructure for Elixir/Ash applications.
Cloud: Digital Ocean (also portable to Hetzner/bare metal).

## Environment Parity

Local and Production environments MUST have the same services:

| Service         | Local (K3d)      | Production (DO)  |
|-----------------|------------------|------------------|
| K3s             | k3d cluster      | Droplet          |
| NGINX Ingress   | :80/:443         | :80/:443         |
| Stress Lab      | x2 pods          | x2 pods          |
| PostgreSQL      | :5432            | :5432            |
| MinIO           | :9000            | :9000            |
| Argo CD         | :30080           | :30080           |

When adding a service to one environment, add it to both.

## Architecture (3 Nodes)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VPS CONTROL                                    │
│  K3s Server │ Argo CD │ CoreDNS │ Scheduler                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
              ┌─────────────────────┴─────────────────────┐
              │                                           │
              ▼                                           ▼
┌───────────────────────────────────┐   ┌───────────────────────────────────┐
│           VPS APP                 │   │           VPS DATA                │
│  ─────────────────────────────    │   │  ─────────────────────────────    │
│  NGINX Ingress (:80/:443)         │   │  PostgreSQL (:5432)               │
│  stress-lab Pod 1                 │   │  MinIO (:9000)                    │
│  stress-lab Pod 2                 │   │                                   │
└───────────────────────────────────┘   └───────────────────────────────────┘
```

## URLs

### Production (DigitalOcean)
- App: http://104.248.237.80/
- Argo CD: http://104.248.237.80:30080 (admin / YNQt9-dw0pzWbJAl)
- SSH: `ssh -i ~/.ssh/id_ed25519_oss_cloud_lab root@104.248.237.80`

### Local (K3d)
- App: http://localhost/
- Argo CD: http://localhost:30080

## API Endpoints

```bash
# Status (replace localhost with 104.248.237.80 for prod)
curl http://localhost/
curl http://localhost/health
curl http://localhost/metrics

# Stress tests
curl http://localhost/cpu/500      # CPU burn 500ms
curl http://localhost/db/10        # 10 DB queries
curl http://localhost/memory/50    # Alloc 50MB

# S3/MinIO
curl -X POST http://localhost/upload/file.txt -H "Content-Type: text/plain" -d "content"
curl http://localhost/download/file.txt
curl http://localhost/files
```

## Scripts

```bash
# === LOCAL (K3d) ===
./local/start.sh              # Create cluster + deploy all services
./local/stop.sh               # Stop cluster (preserves data)
./local/destroy.sh            # Delete cluster completely

# === PRODUCTION (DigitalOcean) ===
./scripts/install-dev.sh      # Full install: tofu + all services
./scripts/deploy-app.sh       # Redeploy app only (fast)
./scripts/destroy-dev.sh      # Destroy everything
```

## File Structure

```
├── CLAUDE.md                 # This file
├── local/                    # Local K3d environment
│   ├── start.sh              # Start local cluster + deploy
│   ├── stop.sh               # Stop local cluster
│   ├── destroy.sh            # Delete local cluster
│   └── k8s/                  # K8s manifests (same as prod)
│       ├── 00-ingress.yaml   # NGINX Ingress (App node)
│       ├── 10-postgresql.yaml # PostgreSQL (Data node)
│       ├── 11-minio.yaml     # MinIO (Data node)
│       └── 20-stress-lab.yaml # App pods (App node)
├── scripts/                  # Production scripts
│   ├── install-dev.sh
│   ├── deploy-app.sh
│   └── destroy-dev.sh
├── stress-lab/               # Application
│   ├── Dockerfile
│   ├── index.js
│   ├── package.json
│   ├── infra-status.html     # Visual diagram (KEEP UPDATED!)
│   └── k3s/deployment.yaml   # Production K8s manifest
└── tofu/                     # OpenTofu (production IaC)
    ├── main.tf
    └── ...
```

## Adding New Services

When adding a new service (e.g., Redis, Prometheus):

1. **Local**: Add manifest to `local/k8s/XX-service.yaml`
2. **Production**: Add to `stress-lab/k3s/` or separate file
3. **Update**: `local/start.sh` if special setup needed
4. **Update**: This file (CLAUDE.md) architecture diagram
5. **Update**: `stress-lab/infra-status.html`

## Stack

| Layer      | Tool                     |
|------------|--------------------------|
| IaC        | OpenTofu                 |
| Runtime    | K3s + Ubuntu 24.04       |
| Local Dev  | K3d (K3s in Docker)      |
| GitOps     | Argo CD                  |
| Ingress    | NGINX Ingress            |
| DB         | PostgreSQL 16            |
| Storage    | MinIO                    |
| Network    | DigitalOcean VPC         |

## Commands

```bash
# K3d (local)
k3d cluster list
kubectl get nodes
kubectl get pods -n stress-lab
kubectl top pods -n stress-lab

# OpenTofu (production)
cd tofu && tofu init && tofu plan && tofu apply

# Digital Ocean
doctl compute droplet list
```

## Constraints

- NO vendor lock-in (no AWS CDK, Azure Blueprints)
- NO hardcoded credentials
- All code and comments in English
- Local and Production must have identical services
