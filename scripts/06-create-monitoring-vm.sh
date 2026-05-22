#!/usr/bin/env bash
set -euo pipefail

VMID=120
NAME="monitoring-vm"
STORAGE="SSD-VMs"
TEMPLATE=9000

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

if ! command -v qm >/dev/null 2>&1; then
  echo "ERROR: qm не найден. Запустите на Proxmox хосте." >&2
  exit 1
fi

if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  echo "ERROR: Шаблон VM $TEMPLATE не найден." >&2
  exit 1
fi

echo "=== Создаем VM $VMID ==="
qm destroy "$VMID" --purge 2>/dev/null || true
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

qm set "$VMID" \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --scsi0 "${STORAGE}:32" \
  --net0 virtio,bridge=vmbr0

qm set "$VMID" \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=dhcp

qm start "$VMID"

echo "MONITORING VM CREATED"
