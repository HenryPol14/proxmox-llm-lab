#!/usr/bin/env bash
# 03-download-cloud-image.sh – загрузка cloud‑image Ubuntu для шаблона
# Скрипт идемпотентен: если образ уже существует, повторная загрузка пропускается
# Использует utils.sh для логирования и отладки
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root


mkdir -p /var/lib/vz/template/qcow2
cd /var/lib/vz/template/qcow2

if [[ -f ubuntu-26.04.img ]]; then
  log_info "Образ ubuntu-26.04.img уже существует. Пропускаю повторную загрузку."
else
  wget -O ubuntu-26.04.img \
    https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img
  echo "IMAGE DOWNLOADED"
fi
