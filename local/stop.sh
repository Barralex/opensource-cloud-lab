#!/bin/bash
# local/stop.sh - Stop local K3d cluster (preserves data)
# Usage: ./local/stop.sh

set -e
export PATH="$HOME/.local/bin:$PATH"

echo "[+] Stopping K3d cluster 'mvp'..."
k3d cluster stop mvp 2>/dev/null || true
docker stop k3d-mvp-agent-app k3d-mvp-agent-data 2>/dev/null || true

echo "[+] Cluster stopped. Data preserved."
echo "    Run ./local/start.sh to resume"
