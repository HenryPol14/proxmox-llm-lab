#!/usr/bin/env bash
set -euo pipefail

# Описание: Клонирует cloud-init шаблон и настраивает виртуальную машину для LLM.
# Использование: sudo scripts/05-create-llm-vm.sh
# Примечание: Рекомендуется проверить VMID, NAME, STORAGE и TEMPLATE перед запуском.

VMID=110
NAME=llm-vm
STORAGE=SSD-VMs
TEMPLATE=9000

# Удаляем старую VM с таким же VMID, если она существует
qm destroy "$VMID" --purge || true

# Клонируем шаблон cloud-init в новую VM
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

# Настройка ресурсов VM
qm set "$VMID" \
  --memory 20480 \
  --cores 4 \
  --cpu host \
  --balloon 0 \
  --numa 1

# Сохраняем параметры платформы и BIOS
qm set "$VMID" \
  --machine q35 \
  --bios ovmf

# Добавляем дополнительные диски для хранения данных LLM
qm set "$VMID" \
  --scsi0 "${STORAGE}:60",discard=on,ssd=1,iothread=1
qm set "$VMID" \
  --scsi1 "${STORAGE}:120",discard=on,ssd=1,iothread=1

# Настраиваем сетевой интерфейс на отдельном мосту vmbr1
qm set "$VMID" \
  --net0 virtio,bridge=vmbr1,queues=8

# Конфигурация cloud-init: пользователь и адрес DHCP
qm set "$VMID" \
  --ciuser ubuntu \
  --ipconfig0 ip=dhcp

# Включаем qemu-guest-agent в конфигурации VM
qm set "$VMID" --agent enabled=1

# Настройка проброса GPU
qm set "$VMID" \
  --hostpci0 01:00.0,pcie=1,rombar=0
qm set "$VMID" --hostpci1 01:00.1

# Включаем сериал и VGA консоль
qm set "$VMID" --serial0 socket --vga serial0

# Запускаем VM
qm start "$VMID"

echo "LLM VM CREATED"

