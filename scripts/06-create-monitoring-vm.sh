#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Клонирует cloud-init шаблон и настраивает виртуальную VM для мониторинга.
# Использование: sudo scripts/06-create-monitoring-vm.sh
# Примечание: Проверьте VMID, NAME, STORAGE и TEMPLATE перед запуском.

VMID=120
NAME=monitoring-vm
STORAGE=SSD-VMs
TEMPLATE=9000

# Удаляем старую VM с тем же VMID, если она существует.
qm destroy "$VMID" --purge || true

# Клонируем шаблон cloud-init для мониторинговой машины.
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

# Настраиваем ресурсы и дисковую подсистему.
qm set "$VMID" \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --scsi0 "${STORAGE}:32" \
  --net0 virtio,bridge=vmbr0

# Конфигурация cloud-init: пользователь и DHCP.
qm set "$VMID" \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=dhcp

# Запускаем мониторинговую виртуальную машину.
qm start "$VMID"

echo "MONITORING VM CREATED"
