#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Устанавливает базовый набор утилит на узел Proxmox.
# Использование: sudo scripts/01-install-proxmox-tools.sh
# Примечание: Запускается на узле Proxmox, где требуется набор инструментов для работы с сетью, дисками и GPU.

# Обновляем кэш пакетов и устанавливаем стандартные утилиты.
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
  qemu-guest-agent \
  net-tools \
  dnsutils \
  pciutils \
  usbutils \
  zip \
  tar

echo "DONE"
