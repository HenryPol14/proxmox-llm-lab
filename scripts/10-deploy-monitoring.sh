#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

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
