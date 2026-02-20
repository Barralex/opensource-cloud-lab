#!/bin/bash
# deploy-app.sh - Deploy only the stress-lab app (fast redeploy)
# Usage: ./scripts/deploy-app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_oss_cloud_lab}"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $1"; }

# Get droplet IP from tofu state
cd "$PROJECT_DIR/tofu"
DROPLET_IP=$(tofu output -raw droplet_ip 2>/dev/null || echo "")

if [ -z "$DROPLET_IP" ]; then
  echo "Error: No droplet found. Run ./scripts/install-dev.sh first"
  exit 1
fi

log "Deploying to $DROPLET_IP..."

# Copy files
scp -i "$SSH_KEY" -r "$PROJECT_DIR/stress-lab/"* root@"$DROPLET_IP":/root/stress-lab/

# Build and deploy
ssh -i "$SSH_KEY" root@"$DROPLET_IP" << 'REMOTE'
set -e
cd /root/stress-lab

# Build and import image
docker build -t stress-lab:latest .
docker save stress-lab:latest | k3s ctr images import -

# Apply manifests (creates if not exists)
kubectl apply -f k3s/deployment.yaml

# Restart deployment to pick up new image (if already exists)
kubectl rollout restart deployment/stress-lab 2>/dev/null || true
kubectl rollout status deployment/stress-lab --timeout=120s

echo "Done!"
REMOTE

log "Deployed! Testing..."
sleep 3
curl -s "http://$DROPLET_IP/health" | head -1
