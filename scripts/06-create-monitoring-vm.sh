#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Ensure bridge vmbr1 is up (no physical NIC)
ip link set vmbr1 up || true

# Идентификатор и имя создаваемой VM.
VMID=120
NAME="monitoring-vm"
# Хранилище и шаблон, от которого будет клонироваться VM.
STORAGE="SSD-VMs"
TEMPLATE=9000
DATA_DISK_SIZE="120"   # GB либо GiB
NETWORK_MODE="${NETWORK_MODE:-manual}"
STATIC_IP="${STATIC_IP:-10.10.10.60}"
STATIC_PREFIX="${STATIC_PREFIX:-24}"
STATIC_GATEWAY="${STATIC_GATEWAY:-10.10.10.1}"
STATIC_DNS="${STATIC_DNS:-10.10.10.1}"


build_ipconfig0() {
  if [[ "$NETWORK_MODE" == "dhcp" ]]; then
    echo "ip=dhcp"
    return
  fi

  if [[ "$NETWORK_MODE" != "manual" ]]; then
    echo "ERROR: NETWORK_MODE поддерживает только dhcp или manual" >&2
    exit 1
  fi

  if [[ -z "$STATIC_IP" || -z "$STATIC_GATEWAY" ]]; then
    echo "ERROR: NETWORK_MODE=manual требует STATIC_IP и STATIC_GATEWAY" >&2
    exit 1
  fi

  local normalized_ip="$STATIC_IP"
  if [[ "$normalized_ip" != */* ]]; then
    normalized_ip="${STATIC_IP}/${STATIC_PREFIX}"
  fi

  # Output ip and gw only; dns will be set via --nameserver
  echo "ip=${normalized_ip},gw=${STATIC_GATEWAY}"
}

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

IPCONFIG0=$(build_ipconfig0)

# Создаем VM только если она еще не существует; иначе обновляем конфигурацию.
echo "=== Подготовка VM $VMID ==="
if qm config "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID уже существует. Обновляю конфигурацию без пересоздания."
else
  qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true
fi

echo "=== Сетевой режим ==="
echo "NETWORK_MODE=${NETWORK_MODE}"
if [[ "$NETWORK_MODE" == "manual" ]]; then
  echo "STATIC_IP=${STATIC_IP}"
  echo "STATIC_PREFIX=${STATIC_PREFIX}"
  echo "STATIC_GATEWAY=${STATIC_GATEWAY}"
fi

# Настраиваем железо и сеть мониторинговой VM.
# Используем bridge vmbr1, чтобы все создаваемые VM были в одной сети.
qm set "$VMID" \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --scsi0 "${STORAGE}:32" \
  --scsi1 "${STORAGE}:${DATA_DISK_SIZE}G,discard=on,ssd=1,iothread=1" \
  --net0 virtio,bridge=vmbr1

# Включаем cloud-init и используем настройки шаблона.
qm set "$VMID" \
  --ciuser ubuntu \
  --ipconfig0 "$IPCONFIG0" \
  --nameserver "$STATIC_DNS"

# Запускаем VM после завершения конфигурации, если она еще не работает.
if qm status "$VMID" 2>/dev/null | grep -q 'running'; then
  log_info "VM $VMID уже запущена"
else
  log_info "Запуск VM $VMID"
  qm start "$VMID"
fi

# Ожидаем QEMU Guest Agent
log_info "Ожидание QEMU Guest Agent"
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    log_info "Guest Agent готов"
    break
  fi
  sleep 2
done

# Исправляем GPT‑таблицу на /dev/sda и расширяем корневой раздел
log_info "Корректировка GPT и рост root‑раздела"
qm guest exec "$VMID" -- bash -lc "
  set -e
  apt-get update -y && apt-get install -y cloud-guest-utils gdisk || true
  sgdisk -e /dev/sda
  partprobe /dev/sda
  growpart /dev/sda 1
  resize2fs /dev/sda1
" || true

log_info "VM $VMID готова. IP: $STATIC_IP"
log_info "Подключение: ssh ubuntu@$STATIC_IP"
# Обновляем known_hosts
ssh-keygen -R "$STATIC_IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$STATIC_IP" >> "$HOME/.ssh/known_hosts"



# Очищаем multipath внутри гостя
qm guest exec "$VMID" -- bash -lc "
  set -e
  systemctl stop multipathd || true
  systemctl disable multipathd || true
  apt-get purge -y multipath-tools || true
  update-initramfs -u
" || true

# Инициализируем дополнительный диск /dev/sdb внутри гостя (GPT, ext4, монтируем в /mnt/data)
log_info "Инициализация диска /dev/sdb"
qm guest exec "$VMID" -- bash -lc "
  set -e
  apt-get update -y && apt-get install -y cloud-guest-utils gdisk || true
  sgdisk -o /dev/sdb
  sgdisk -n 1:0:0 -t 1:8300 /dev/sdb
  partprobe /dev/sdb
  mkfs.ext4 -F /dev/sdb1
  mkdir -p /mnt/data
  echo '/dev/sdb1 /mnt/data ext4 defaults 0 0' >> /etc/fstab
  mount /mnt/data
" || true

echo "MONITORING VM CREATED"
