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

TARGET_DIR="/opt/llm-stack"
TARGET_FILE="${TARGET_DIR}/docker-compose.yml"

mkdir -p "$TARGET_DIR"
if [[ ! -f "$TARGET_FILE" ]]; then
  cat <<'EOF' > "$TARGET_FILE"
services:

  ollama:
    image: ollama/ollama
    container_name: ollama
    restart: unless-stopped

    ports:
      - "11434:11434"

    volumes:
      - ollama:/root/.ollama

    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]

  open-webui:
    image: ghcr.io/open-webui/open-webui:main

    container_name: open-webui
    restart: unless-stopped

    ports:
      - "3000:8080"

    environment:
      OLLAMA_BASE_URL: http://ollama:11434

    volumes:
      - openwebui:/app/backend/data

volumes:
  ollama:
  openwebui:
EOF
fi

cd "$TARGET_DIR"
docker compose up -d
echo "OLLAMA STACK DEPLOYED"
