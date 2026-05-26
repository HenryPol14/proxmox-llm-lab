#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

if ! command -v curl >/dev/null 2>&1; then
  log_error "curl not found."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
else
  log_info "Docker already installed. Skipping installation and start."
fi

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER"
else
  usermod -aG docker "$USER"
fi

docker version
