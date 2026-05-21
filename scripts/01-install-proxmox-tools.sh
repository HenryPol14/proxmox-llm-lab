#!/usr/bin/env bash
set -e
set -euxo pipefail

apt update
apt install -y \
  curl \
  wget \
  vim \
  git \
  htop \
  jq \
  unzip \
  gnupg \
  lsb-release \
  software-properties-common \
  qemu-guest-agent

echo "DONE"
