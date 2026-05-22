#!/usr/bin/env bash
set -euo pipefail

# Описание: Создает виртуальную машину Proxmox на основе Ubuntu Cloud-образа
# и преобразует её в шаблон cloud-init.
# Использование: sudo scripts/04-create-cloudinit-template.sh
# Примечание: При необходимости отредактируйте VMID, STORAGE и путь к IMG.

VMID=9000
STORAGE=SSD-VMs
IMG=/var/lib/vz/template/qcow2/ubuntu-26.04.img

# Проверяем, что образ cloud-init существует
if [[ ! -f "$IMG" ]]; then
  echo "ERROR: Образ не найден: $IMG" >&2
  echo "Сначала запустите scripts/03-download-cloud-image.sh" >&2
  exit 1
fi

# Удаляем VM с таким же VMID, если он уже существует
qm destroy "$VMID" --purge || true

# Создаем заготовку VM, которую потом превратим в шаблон
qm create "$VMID" \
  --name ubuntu-26-template \
  --memory 4096 \
  --cores 4 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr0

# Настраиваем EFI-диск для загрузки и импортируем Ubuntu cloud-образ
qm set "$VMID" --efidisk0 "${STORAGE}:1"
qm importdisk "$VMID" "$IMG" "$STORAGE"

# Определяем имя импортированного диска и переводим его в scsi0
IMPORT_DISK=$(qm config "$VMID" | awk '/unused0/ { split($2, a, ","); print a[1] }')
qm set "$VMID" \
  --scsihw virtio-scsi-single \
  --scsi0 "${IMPORT_DISK}",discard=on,ssd=1,iothread=1

# Добавляем cloud-init диск и задаем порядок загрузки
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0

# Настройка консоли и видео для управления через serial
qm set "$VMID" \
  --serial0 socket \
  --vga serial0

# Включаем qemu-guest-agent в конфигурации VM
qm set "$VMID" --agent enabled=1

# Преобразуем VM в шаблон для последующего клонирования
qm template "$VMID"

echo "TEMPLATE CREATED"

