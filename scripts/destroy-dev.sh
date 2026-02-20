#!/bin/bash
# destroy-dev.sh - Destroy dev environment
# Usage: ./scripts/destroy-dev.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
  source "$PROJECT_DIR/.env"
fi

echo "This will destroy all infrastructure!"
read -p "Are you sure? (y/N) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
  cd "$PROJECT_DIR/tofu"
  tofu destroy -auto-approve
  echo "Done."
fi
