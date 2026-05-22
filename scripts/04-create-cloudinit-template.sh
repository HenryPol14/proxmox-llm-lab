#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Создает Proxmox VM на основе Ubuntu cloud-образа и превращает её в шаблон cloud-init.
# Использование: sudo scripts/04-create-cloudinit-template.sh
# Примечание: Требует установленного пакета libguestfs-tools для virt-customize.
#            В шаблон добавляется QEMU Guest Agent, но сетевые параметры cloud-init задаются при создании клона.

VMID=9000
STORAGE=SSD-VMs
IMG="/var/lib/vz/template/qcow2/ubuntu-26.04.img"

# 1. Проверяем, что образ существует.
if [[ ! -f "$IMG" ]]; then
  echo "ERROR: Образ не найден: $IMG" >&2
  echo "Запустите scripts/03-download-cloud-image.sh" >&2
  exit 1
fi

# 2. Проверяем наличие virt-customize.
if ! command -v virt-customize >/dev/null 2>&1; then
  echo "ERROR: virt-customize не найден. Установите libguestfs-tools." >&2
  exit 1
fi

# 3. Готовим образ: устанавливаем qemu-guest-agent и очищаем machine-id.
echo "=== Подготовка cloud-образа ==="
virt-customize -a "$IMG" \
  --install qemu-guest-agent,curl \
  --run-command "sed -i 's/^#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf || true" \
  --truncate /etc/machine-id

# 4. Удаляем VM с таким же VMID, если она уже существует.
echo "=== Создаем шаблонную VM ==="
qm destroy "$VMID" --purge 2>/dev/null || true

qm create "$VMID" \
  --name ubuntu-26-template \
  --ostype l26 \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr0

# 5. Настраиваем EFI-диск и импортируем qcow2 образ в хранилище.
echo "=== Импорт диска ==="
qm set "$VMID" --efidisk0 "${STORAGE}:0"
qm importdisk "$VMID" "$IMG" "$STORAGE"

# 6. Определяем имя импортированного диска и подключаем его как scsi0.
DISK_VOL=$(qm config "$VMID" | awk '/unused0:/ {print $2}' | cut -d, -f1)
if [[ -z "$DISK_VOL" ]]; then
  echo "ERROR: Не удалось определить импортированный диск." >&2
  exit 1
fi

qm set "$VMID" \
  --scsihw virtio-scsi-single \
  --scsi0 "$DISK_VOL",discard=on,ssd=1,iothread=1

# 7. Добавляем cloud-init диск и конфигурацию загрузки.
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --serial0 socket --vga serial0

# 8. Преобразуем VM в шаблон.
echo "=== Преобразуем VM в шаблон ==="
qm template "$VMID"
echo "DONE: Template $VMID создан."
