#!/usr/bin/env bash
set -euo pipefail

# Конфигурация (можно вынести в отдельный .env файл)
VMID=${1:-9000}
STORAGE=${2:-SSD-VMs}
IMG_PATH="/var/lib/vz/template/qcow2/ubuntu-26.04.img"
VM_NAME="ubuntu-24-template" # Ubuntu 26 еще не вышла, вероятно опечатка
MEM=2048
CORES=2
BRIDGE="vmbr0"

# 1. Проверки
if [[ $EUID -ne 0 ]]; then
   echo "Ошибка: Запустите скрипт от имени root (sudo)" >&2
   exit 1
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "ERROR: Образ не найден: $IMG_PATH" >&2
  exit 1
fi

echo "--- Создание шаблона VM $VMID ($VM_NAME) ---"

# 2. Очистка старого шаблона
if qm status "$VMID" >/dev/null 2>&1; then
    echo "Удаление старой ВМ..."
    qm destroy "$VMID" --purge
fi

# 3. Создание ВМ
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEM" \
  --cores "$CORES" \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge="$BRIDGE" \
  --agent enabled=1 \
  --tablet 0 # Отключение планшета экономит ресурсы CPU

# 4. Работа с дисками
# Стало (для LVM-Thin):
qm set "$VMID" --efidisk0 "${STORAGE}:0"

echo "Импорт диска (это может занять время)..."
# Импортируем и сразу узнаем имя тома
IMPORT_RESULT=$(qm importdisk "$VMID" "$IMG_PATH" "$STORAGE")
# Извлекаем имя созданного тома из вывода (надежнее, чем awk по конфигу)
DISK_VOL=$(echo "$IMPORT_RESULT" | grep -o "unused[0-9]" | head -1 || echo "")
# Если grep не сработал, пробуем старый метод через config
if [[ -z "$DISK_VOL" ]]; then
    DISK_VOL=$(qm config "$VMID" | awk '/unused0/ {split($2, a, ","); print a[1]}')
fi

qm set "$VMID" --scsihw virtio-scsi-single \
  --scsi0 "${STORAGE}:${DISK_VOL/unused0:/}",discard=on,ssd=1,iothread=1

# 5. Cloud-Init и загрузка
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --serial0 socket --vga serial0

# Сразу задаем базовые настройки Cloud-init (чтобы не делать это вручную в каждой новой ВМ)
qm set "$VMID" --ipconfig0 ip=dhcp
# qm set "$VMID" --sshkeys ~/.ssh/id_rsa.pub # Опционально: добавьте свой ключ

# 6. Финализация
echo "Преобразование в шаблон..."
qm template "$VMID"

echo "Успешно! Шаблон $VMID создан."
