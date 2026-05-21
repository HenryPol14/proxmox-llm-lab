#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Install common utilities on a Proxmox host.
# Usage: sudo scripts/01-install-proxmox-tools.sh
# Note: Run on the Proxmox node where you want these packages installed.

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
