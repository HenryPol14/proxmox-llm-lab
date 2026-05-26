#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Поднимаем bridge vmbr1 (в системе нет физ. NIC)
ip link set vmbr1 up || true

# Параметры VM (можно переопределить через переменные окружения)
VMID=${1:-110}
NAME="llm-server"
TEMPLATE=9000
STORAGE="SSD-VMs"
MEM=20480   # MB
CORES=4
SYS_DISK_SIZE="44G"
DATA_DISK_SIZE="120"   # GB или GiB

# Сетевые параметры (ручной режим)
NETWORK_MODE="manual"
STATIC_IP="${STATIC_IP:-10.10.10.50}"
STATIC_PREFIX="${STATIC_PREFIX:-24}"
STATIC_GATEWAY="${STATIC_GATEWAY:-10.10.10.1}"
STATIC_DNS="${STATIC_DNS:-1.1.1.1}"

# Проверяем наличие шаблона
if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  log_error "Шаблон VM $TEMPLATE не найден"
  exit 1
fi

# Клонирование / обновление конфигурации VM
if qm config "$VMID" >/dev/null 2>&1; then
  log_info "VM $VMID уже существует – обновляем конфигурацию без пересоздания"
else
  log_info "Клонирование шаблона $TEMPLATE → VM $VMID"
  qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true
fi

# Формируем ipconfig0 (ip/gw без dns, dns задаём отдельным параметром)
IPCONFIG="ip=${STATIC_IP}/${STATIC_PREFIX},gw=${STATIC_GATEWAY}"

# Настраиваем основные параметры VM
qm set "$VMID" \
  --memory "$MEM" \
  --cores "$CORES" \
  --cpu host \
  --balloon 0 \
  --numa 1 \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr1,queues=8 \
  --ciuser ubuntu \
  --ipconfig0 "$IPCONFIG" \
  --nameserver "$STATIC_DNS"

# Добавляем GPU, если обнаружен
GPU_ADDR=$(lspci -d 10de: | awk 'NR==1 {print $1}')
if [[ -n "$GPU_ADDR" ]]; then
  log_info "Настройка GPU $GPU_ADDR"
  qm set "$VMID" --hostpci0 "$GPU_ADDR,pcie=1,x-vga=1"
  # Blacklist nouveau driver внутри гостевой ОС и обновляем initramfs
  qm guest exec "$VMID" -- bash -lc '
    echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
    update-initramfs -u
  '
else
  log_warn "NVIDIA GPU не найден – пропускаем проброс"
fi

# Размеры дисков
qm resize "$VMID" scsi0 "$SYS_DISK_SIZE" || true
# Приведение DATA_DISK_SIZE к GiB (если указано с G/g)
if [[ "$DATA_DISK_SIZE" =~ ^([0-9]+)[Gg]?$ ]]; then
  DATA_GIB="${BASH_REMATCH[1]}"
else
  DATA_GIB="$DATA_DISK_SIZE"
fi
qm set "$VMID" --scsi1 "${STORAGE}:${DATA_GIB},discard=on,ssd=1,iothread=1"
qm set "$VMID" --onboot 1

# Запускаем VM, если она ещё не запущена
if qm status "$VMID" 2>/dev/null | grep -q 'running'; then
  log_info "VM $VMID уже запущена"
else
  log_info "Запуск VM $VMID"
  qm start "$VMID"
fi

# Ожидание QEMU Guest Agent (не нужен DHCP, так как IP статический)
log_info "Ожидание QEMU Guest Agent"
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    log_info "Guest Agent готов"
    break
  fi
  sleep 2
done

log_info "VM $VMID готова. IP: $STATIC_IP"
log_info "Подключение: ssh ubuntu@$STATIC_IP"
# Удаляем старый ключ хоста из known_hosts (если существует) и добавляем новый
ssh-keygen -R "$STATIC_IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$STATIC_IP" >> "$HOME/.ssh/known_hosts"

# Исправляем GPT‑разметку внутри гостя (перемещаем backup‑таблицу и расширяем корневой раздел)
qm guest exec "$VMID" -- bash -lc "
  set -e
  apt-get update -y && apt-get install -y cloud-guest-utils gdisk || true
  sgdisk -e /dev/sda
  partprobe /dev/sda
  growpart /dev/sda 1
  resize2fs /dev/sda1
" || true

# Очищаем multipath внутри гостя
qm guest exec "$VMID" -- bash -lc "
  set -e
  systemctl stop multipathd || true
  systemctl disable multipathd || true
  apt-get purge -y multipath-tools || true
  update-initramfs -u
" || true

