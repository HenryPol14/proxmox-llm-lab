#!/usr/bin/env bash
set -euo pipefail

# Deploy monitoring stack using docker compose
# Usage: scripts/10-deploy-monitoring.sh
docker compose -f docker/monitoring/docker-compose.yml up -d

