#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Разворачивает стек мониторинга с помощью Docker Compose.
# Использование: sudo scripts/10-deploy-monitoring.sh
# Примечание: Используется docker-compose файл из папки docker/monitoring.

# Запускаем стек мониторинга в фоновом режиме.
docker compose -f docker/monitoring/docker-compose.yml up -d

echo "MONITORING STACK DEPLOYED"
