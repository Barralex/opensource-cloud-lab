#!/bin/bash
# local/destroy.sh - Destroy local K3d cluster completely
# Usage: ./local/destroy.sh

set -e
export PATH="$HOME/.local/bin:$PATH"

echo "[!] This will DELETE the cluster and all data."
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 0
fi

echo "[+] Removing agent containers..."
docker rm -f k3d-mvp-agent-app k3d-mvp-agent-data 2>/dev/null || true

echo "[+] Deleting K3d cluster 'mvp'..."
k3d cluster delete mvp 2>/dev/null || true

echo "[+] Cluster destroyed."
