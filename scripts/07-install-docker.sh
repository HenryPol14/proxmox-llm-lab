#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Install Docker using the official convenience script.
# Usage: sudo scripts/07-install-docker.sh
# Note: This script adds the current user to the `docker` group.
curl -fsSL https://get.docker.com | sh

systemctl enable docker
systemctl start docker

usermod -aG docker "$USER"

docker version