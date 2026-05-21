#!/usr/bin/env bash
set -e
set -euxo pipefail

mkdir -p /opt/llm-stack
cp docker-compose.yml /opt/llm-stack/

cd /opt/llm-stack

docker compose up -d

echo "OLLAMA STACK DEPLOYED"
