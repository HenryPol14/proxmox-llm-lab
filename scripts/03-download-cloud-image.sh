#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Загружает Ubuntu cloud-образ для создания шаблона Proxmox.
# Использование: sudo scripts/03-download-cloud-image.sh
# Примечание: Образ сохраняется в /var/lib/vz/template/qcow2.

mkdir -p /var/lib/vz/template/qcow2
cd /var/lib/vz/template/qcow2

# Скачиваем актуальный Ubuntu 26.04 cloud image.
wget -O ubuntu-26.04.img \
  https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img

echo "IMAGE DOWNLOADED"
