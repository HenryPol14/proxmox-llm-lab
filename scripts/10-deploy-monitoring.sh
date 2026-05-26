#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker не найден." >&2
  exit 1
fi

if [[ -f docker/monitoring/docker-compose.yml ]]; then
  docker compose -f docker/monitoring/docker-compose.yml up -d
  echo "MONITORING STACK DEPLOYED"
else
  echo "ERROR: файл docker/monitoring/docker-compose.yml не найден." >&2
  exit 1
fi
