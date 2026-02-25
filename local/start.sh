#!/bin/bash
# local/start.sh - Start local K3d cluster (3 nodes: control, app, data)
# Usage: ./local/start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Check dependencies
check_deps() {
  # Docker
  if ! docker info >/dev/null 2>&1; then
    warn "Docker not running. Starting Colima..."
    colima start 2>/dev/null || {
      echo "Install Colima: brew install colima && colima start"
      exit 1
    }
  fi

  # K3d
  if ! command -v k3d >/dev/null 2>&1; then
    log "Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | USE_SUDO=false K3D_INSTALL_DIR=$HOME/.local/bin bash
  fi
}

# Create cluster
create_cluster() {
  if k3d cluster list | grep -q "mvp"; then
    log "Cluster 'mvp' already exists"
    return
  fi

  log "Creating K3d cluster 'mvp' (3 nodes)..."

  # Create cluster with 1 server
  k3d cluster create mvp \
    --servers 1 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --port "30080:30080@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0"

  # Add agent nodes with labels
  log "Adding agent nodes..."

  # Agent 0 = VPS App
  docker run -d --name k3d-mvp-agent-app \
    --network k3d-mvp \
    --memory=2g --cpus=2 \
    -e K3S_URL=https://k3d-mvp-server-0:6443 \
    -e K3S_TOKEN=$(docker exec k3d-mvp-server-0 cat /var/lib/rancher/k3s/server/node-token) \
    --privileged \
    rancher/k3s:v1.31.5-k3s1 agent

  # Agent 1 = VPS Data
  docker run -d --name k3d-mvp-agent-data \
    --network k3d-mvp \
    --memory=1g --cpus=1 \
    -e K3S_URL=https://k3d-mvp-server-0:6443 \
    -e K3S_TOKEN=$(docker exec k3d-mvp-server-0 cat /var/lib/rancher/k3s/server/node-token) \
    --privileged \
    rancher/k3s:v1.31.5-k3s1 agent

  # Wait for nodes
  log "Waiting for nodes..."
  sleep 10

  # Label nodes
  log "Labeling nodes..."
  kubectl label node $(docker ps --filter name=k3d-mvp-agent-app --format "{{.ID}}" | head -c 12) node-role.kubernetes.io/app=true 2>/dev/null || true
  kubectl label node $(docker ps --filter name=k3d-mvp-agent-data --format "{{.ID}}" | head -c 12) node-role.kubernetes.io/data=true 2>/dev/null || true
}

# Deploy services
deploy_services() {
  log "Deploying services..."

  # Create namespace
  kubectl create namespace stress-lab 2>/dev/null || true

  # Apply all manifests
  kubectl apply -f "$SCRIPT_DIR/k8s/"

  # Wait for deployments
  log "Waiting for pods..."
  kubectl wait --for=condition=ready pod -l app=postgresql -n stress-lab --timeout=120s 2>/dev/null || true
  kubectl wait --for=condition=ready pod -l app=minio -n stress-lab --timeout=120s 2>/dev/null || true
  kubectl wait --for=condition=ready pod -l app=stress-lab -n stress-lab --timeout=120s 2>/dev/null || true
}

# Install NGINX Ingress on App node
install_ingress() {
  log "Installing NGINX Ingress..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

  log "Waiting for Ingress controller..."
  sleep 10

  # Force Ingress to App node
  kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"node-role.kubernetes.io/app": "true"}}]' 2>/dev/null || true

  # Make it LoadBalancer for K3d
  kubectl patch svc ingress-nginx-controller -n ingress-nginx \
    -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true

  # Wait for it to be ready
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s 2>/dev/null || true
}

# Build and load app image
build_app() {
  log "Building stress-lab image..."
  docker build -t stress-lab:local "$SCRIPT_DIR/../stress-lab/"

  log "Loading image into cluster..."
  docker save stress-lab:local | docker exec -i k3d-mvp-agent-app ctr images import -
}

# Create MinIO bucket
setup_minio() {
  log "Creating MinIO bucket..."
  sleep 5
  kubectl exec -n stress-lab deployment/minio -- sh -c "
    curl -sLo /tmp/mc https://dl.min.io/client/mc/release/linux-arm64/mc 2>/dev/null || curl -sLo /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x /tmp/mc
    /tmp/mc alias set local http://localhost:9000 admin admin123456
    /tmp/mc mb local/stress-lab 2>/dev/null || true
  " 2>/dev/null || true
}

# Main
main() {
  log "=== Starting Local K3d Environment ==="
  check_deps
  create_cluster
  install_ingress
  build_app
  deploy_services
  setup_minio

  echo ""
  log "=== Local Environment Ready ==="
  echo ""
  echo "  App:     http://localhost/"
  echo "  Health:  http://localhost/health"
  echo "  Argo CD: http://localhost:30080"
  echo ""
  echo "  Nodes:"
  kubectl get nodes
  echo ""
  echo "  Pods:"
  kubectl get pods -n stress-lab
}

main
