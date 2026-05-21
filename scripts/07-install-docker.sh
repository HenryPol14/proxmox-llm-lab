#!/usr/bin/env bash
set -e
set -euxo pipefail
curl -fsSL https://get.docker.com | sh

systemctl enable docker
systemctl start docker

usermod -aG docker "$USER"

docker version