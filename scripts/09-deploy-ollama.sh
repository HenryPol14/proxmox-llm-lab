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

mkdir -p /opt/llm-stack
cp docker-compose.yml /opt/llm-stack/
cd /opt/llm-stack

docker compose up -d
echo "OLLAMA STACK DEPLOYED"
