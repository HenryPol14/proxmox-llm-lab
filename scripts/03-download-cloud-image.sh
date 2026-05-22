#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

mkdir -p /var/lib/vz/template/qcow2
cd /var/lib/vz/template/qcow2

wget -O ubuntu-26.04.img \
  https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img

echo "IMAGE DOWNLOADED"
