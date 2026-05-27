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

# --- Установка базовых пакетов и подготовка шаблона ---
# Вместо virt-customize будем запускать временную VM, устанавливать необходимые пакеты,
# включать сервисы, настраивать sysctl и очищать cloud‑init.
# Это обеспечивает idempotent‑построение шаблона с нужными инструментами.

# После создания и импорта диска запустим VM, установим пакеты и настроим окружение.
log_info "Запуск временной VM $VMID для подготовки шаблона"
qm start "$VMID"

# Ожидание QEMU Guest Agent
log_info "Ожидание QEMU Guest Agent в шаблоне"
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    log_info "Guest Agent готов"
    break
  fi
  sleep 2
done

# Установка базовых пакетов и включение сервисов
qm guest exec "$VMID" -- bash -lc '
  set -e
  apt-get update -y
  apt-get install -y qemu-guest-agent cloud-init docker.io htop curl git nvtop pciutils ubuntu-drivers-common
  systemctl enable qemu-guest-agent
  systemctl enable docker
'

# Настройка sysctl
qm guest exec "$VMID" -- bash -lc '
  cat > /etc/sysctl.d/99-llm.conf <<EOF
vm.swappiness=5
vm.max_map_count=1048576
fs.inotify.max_user_watches=1048576
EOF
  sysctl --system
'

# Очистка cloud‑init и machine‑id
qm guest exec "$VMID" -- bash -lc '
  cloud-init clean
  truncate -s 0 /etc/machine-id
  rm -f /var/lib/dbus/machine-id
  sync
'

# Остановка VM и преобразование в шаблон
log_info "Остановка VM $VMID перед конвертацией в шаблон"
qm shutdown "$VMID" || qm stop "$VMID"
# Ждём выключения
while qm status "$VMID" | grep -q running; do sleep 1; done



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
