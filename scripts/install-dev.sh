#!/bin/bash
# install-dev.sh - Deploy complete dev environment
# Usage: ./scripts/install-dev.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_oss_cloud_lab}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
  log "Loading .env"
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

[ -z "$DIGITALOCEAN_TOKEN" ] && error "DIGITALOCEAN_TOKEN not set. Add it to .env"
export DIGITALOCEAN_TOKEN

# Run OpenTofu
log "Running OpenTofu..."
cd "$PROJECT_DIR/tofu"
tofu init -upgrade
tofu apply -auto-approve

# Get droplet IP
DROPLET_IP=$(tofu output -raw droplet_ip)
log "Droplet IP: $DROPLET_IP"

# Wait for SSH
log "Waiting for SSH..."
for i in {1..30}; do
  if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$DROPLET_IP" "echo ok" 2>/dev/null; then
    break
  fi
  echo -n "."
  sleep 10
done
echo ""

# Wait for infrastructure to be ready
log "Waiting for infrastructure setup (this takes ~3-5 minutes on first run)..."
for i in {1..60}; do
  if ssh -i "$SSH_KEY" root@"$DROPLET_IP" "test -f /root/.infra_ready" 2>/dev/null; then
    log "Infrastructure ready!"
    break
  fi
  echo -n "."
  sleep 10
done
echo ""

# Check if infra is ready
if ! ssh -i "$SSH_KEY" root@"$DROPLET_IP" "test -f /root/.infra_ready" 2>/dev/null; then
  warn "Infrastructure not ready yet. Check cloud-init logs:"
  echo "  ssh -i $SSH_KEY root@$DROPLET_IP 'tail -f /var/log/cloud-init-output.log'"
  exit 1
fi

# Deploy stress-lab app
log "Deploying stress-lab app..."

# Create temp dir on server and copy files
ssh -i "$SSH_KEY" root@"$DROPLET_IP" "mkdir -p /root/stress-lab"
scp -i "$SSH_KEY" -r "$PROJECT_DIR/stress-lab/"* root@"$DROPLET_IP":/root/stress-lab/

# Build and deploy on server
ssh -i "$SSH_KEY" root@"$DROPLET_IP" << 'REMOTE'
set -e
cd /root/stress-lab

# Build Docker image
echo "Building stress-lab image..."
docker build -t stress-lab:latest .

# Import to k3s containerd
echo "Importing image to k3s..."
docker save stress-lab:latest | k3s ctr images import -

# Apply Kubernetes manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f k3s/deployment.yaml

# Wait for deployment
echo "Waiting for deployment..."
kubectl rollout status deployment/stress-lab --timeout=120s

echo "Done!"
REMOTE

# Show status
log "Deployment complete!"
echo ""
echo "=== Access URLs ==="
echo "  App:     http://$DROPLET_IP/"
echo "  Health:  http://$DROPLET_IP/health"
echo "  CPU:     http://$DROPLET_IP/cpu/500"
echo "  DB:      http://$DROPLET_IP/db/10"
echo ""

# Get Argo CD password
ARGOCD_PASS=$(ssh -i "$SSH_KEY" root@"$DROPLET_IP" "cat /root/argocd-password.txt 2>/dev/null | cut -d: -f2 | tr -d ' '" || echo "unknown")
echo "  Argo CD: http://$DROPLET_IP:30080"
echo "           admin / $ARGOCD_PASS"
echo ""

# Test the app
log "Testing app..."
sleep 5
if curl -s "http://$DROPLET_IP/health" | grep -q "healthy"; then
  log "App is healthy!"
else
  warn "App health check failed. Check pods: kubectl get pods"
fi
