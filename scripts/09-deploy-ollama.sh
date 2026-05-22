#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Разворачивает стек Ollama с помощью Docker Compose.
# Использование: sudo scripts/09-deploy-ollama.sh
# Примечание: Ожидает наличие docker-compose.yml рядом со скриптом или в указанных путях.

# Создаём директорию для стеков и копируем файлы конфигурации.
mkdir -p /opt/llm-stack
cp docker-compose.yml /opt/llm-stack/

# Переходим в директорию и запускаем сервисы.
cd /opt/llm-stack

docker compose up -d

echo "OLLAMA STACK DEPLOYED"
