#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Deploy the Ollama LLM stack using Docker Compose.
# Usage: sudo scripts/09-deploy-ollama.sh
# Note: Expects a `docker-compose.yml` in the same directory or adjusts path.

mkdir -p /opt/llm-stack
cp docker-compose.yml /opt/llm-stack/

cd /opt/llm-stack

docker compose up -d

echo "OLLAMA STACK DEPLOYED"
