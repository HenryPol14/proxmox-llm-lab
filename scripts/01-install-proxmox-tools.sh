#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

apt update
apt install -y \
  curl wget vim git htop jq unzip gnupg lsb-release \
  qemu-guest-agent net-tools dnsutils pciutils usbutils zip tar

echo "DONE"
