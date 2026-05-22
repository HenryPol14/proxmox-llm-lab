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
if [[ -f "$TARGET_FILE" ]]; then
  echo "Файл $TARGET_FILE уже существует. Сохраняю текущую конфигурацию, не перезаписываю."
else
  cp docker-compose.yml "$TARGET_FILE"
fi

cd "$TARGET_DIR"
docker compose up -d
echo "OLLAMA STACK DEPLOYED"
