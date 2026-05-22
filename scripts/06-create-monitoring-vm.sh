#!/usr/bin/env bash
set -euo pipefail

# Идентификатор и имя создаваемой VM.
VMID=120
NAME="monitoring-vm"
# Хранилище и шаблон, от которого будет клонироваться VM.
STORAGE="SSD-VMs"
TEMPLATE=9000

# Скрипт должен запускаться от root, потому что управляет Proxmox и qm.
if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

# Проверяем наличие утилиты qm на хосте.
if ! command -v qm >/dev/null 2>&1; then
  echo "ERROR: qm не найден. Запустите на Proxmox хосте." >&2
  exit 1
fi

# Проверяем, что базовый шаблон действительно существует.
if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  echo "ERROR: Шаблон VM $TEMPLATE не найден." >&2
  exit 1
fi

# Удаляем старую VM с таким ID, если она уже есть, чтобы избежать конфликтов.
echo "=== Создаем VM $VMID ==="
qm destroy "$VMID" --purge 2>/dev/null || true
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

# Настраиваем железо и сеть мониторинговой VM.
# Используем bridge vmbr1, чтобы все создаваемые VM были в одной сети.
qm set "$VMID" \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --scsi0 "${STORAGE}:32" \
  --net0 virtio,bridge=vmbr1

# Включаем cloud-init и передаем SSH ключ для доступа к VM.
qm set "$VMID" \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=dhcp

# Запускаем VM после завершения конфигурации.
qm start "$VMID"

echo "MONITORING VM CREATED"
