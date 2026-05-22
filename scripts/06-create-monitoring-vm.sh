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

# Создаем VM только если она еще не существует; иначе обновляем конфигурацию.
echo "=== Подготовка VM $VMID ==="
if qm config "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID уже существует. Обновляю конфигурацию без пересоздания."
else
  qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true
fi

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

# Запускаем VM после завершения конфигурации, если она еще не работает.
if qm status "$VMID" 2>/dev/null | grep -q 'running'; then
  echo "VM $VMID уже запущена."
else
  qm start "$VMID"
fi

echo "MONITORING VM CREATED"
