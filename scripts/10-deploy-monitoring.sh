#!/usr/bin/env bash
set -euo pipefail

# Deploy monitoring stack using docker compose
# Usage: scripts/10-deploy-monitoring.sh
# Usage: sudo scripts/10-deploy-monitoring.sh
# Note: Runs `docker compose up -d` for monitoring stack.
docker compose -f docker/monitoring/docker-compose.yml up -d

