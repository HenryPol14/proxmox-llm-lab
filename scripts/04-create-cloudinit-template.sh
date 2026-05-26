#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Конфигурация
VMID=9000
STORAGE=SSD-VMs
IMG="/var/lib/vz/template/qcow2/ubuntu-26.04.img"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}"

if [[ ! -f "$IMG" ]]; then
  log_error "Образ не найден: $IMG"
  exit 1
fi

if [[ ! -f "$SSH_PUBLIC_KEY" ]]; then
  log_error "SSH public key not found: $SSH_PUBLIC_KEY"
  exit 1
fi

echo "--- Модификация образа (Console & Agent) ---"
# 1. Включаем вывод в Serial консоль (ttyS0)
# 2. Устанавливаем Guest Agent
# 3. Сбрасываем Machine-ID для уникальных IP по DHCP
virt-customize -a "$IMG" \
  --install qemu-guest-agent,curl \
  --run-command "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub" \
  --run-command "update-grub" \
  --run-command "truncate -s 0 /etc/machine-id" \
  --truncate /etc/machine-id

echo "--- Подготовка шаблона $VMID ---"
if qm config "$VMID" >/dev/null 2>&1; then
  if [[ "${FORCE_REBUILD:-0}" == "1" ]]; then
    echo "FORCE_REBUILD=1: удаляю старый шаблон $VMID и создаю заново."
    qm destroy "$VMID" --purge
  else
    echo "Шаблон $VMID уже существует. Обновляю только cloud-init ключ и оставляю шаблон без пересоздания."
    qm set "$VMID" \
      --ciuser ubuntu \
      --sshkey "$SSH_PUBLIC_KEY"
    echo "SSH-ключ в шаблоне обновлен. Если нужно полностью пересоздать шаблон, запустите скрипт с FORCE_REBUILD=1."
    exit 0
  fi
fi

qm create "$VMID" \
  --name "ubuntu-26-template" \
  --ostype l26 \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr1 # Сразу ставим на внутренний мост

# Импорт диска
qm set "$VMID" --efidisk0 "${STORAGE}:0"
qm importdisk "$VMID" "$IMG" "$STORAGE"

# Получаем имя диска для LVM-Thin
DISK_VOL=$(qm config "$VMID" | awk '/unused0:/ {print $2}' | cut -d, -f1)
qm set "$VMID" --scsihw virtio-scsi-single --scsi0 "$DISK_VOL",discard=on,ssd=1

# Настройки Cloud-Init
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --serial0 socket --vga serial0
qm set "$VMID" \
  --ciuser ubuntu \
  --sshkey "$SSH_PUBLIC_KEY"

echo "Converting to template..."
qm template "$VMID"
echo "УСПЕХ: Шаблон готов. Теперь запускайте скрипт 05."
