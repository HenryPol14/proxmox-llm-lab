#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Ensure bridge vmbr1 is up (no physical NIC)
ip link set vmbr1 up || true

# Variables (can be overridden via environment)
VMID=${1:-110}
NAME="llm-server"
TEMPLATE=9000
STORAGE="SSD-VMs"
MEM=20480   # MB
CORES=4
SYS_DISK_SIZE="44G"
DATA_DISK_SIZE="${DATA_DISK_SIZE:-120}"   # GB (or GiB)
NETWORK_MODE="manual"
STATIC_IP="${STATIC_IP:-10.10.10.50}"
STATIC_PREFIX="${STATIC_PREFIX:-24}"
STATIC_GATEWAY="${STATIC_GATEWAY:-10.10.10.1}"
STATIC_DNS="${STATIC_DNS:-1.1.1.1}"

# Verify that the base template exists
if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  log_error "Шаблон VM $TEMPLATE не найден"
  exit 1
fi

# Clone the VM if it does not exist yet
if qm config "$VMID" >/dev/null 2>&1; then
  log_info "VM $VMID уже существует – обновляем конфигурацию"
else
  log_info "Клонирование шаблона $TEMPLATE → VM $VMID"
  qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true
fi

# Build ipconfig0 (IP + gateway, DNS будет передан отдельным параметром)
IPCONFIG="ip=${STATIC_IP}/${STATIC_PREFIX},gw=${STATIC_GATEWAY}"

# Configure hardware, network and disks
if ! qm set "$VMID" \
  --memory "$MEM" \
  --cores "$CORES" \
  --cpu host \
  --balloon 0 \
  --numa 1 \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr1,queues=8 \
  --ciuser ubuntu \
  --ipconfig0 "$IPCONFIG" \
  --nameserver "$STATIC_DNS" \
  --scsi0 "${STORAGE}:32" \
  --scsi1 "${STORAGE}:${DATA_DISK_SIZE},discard=on,ssd=1,iothread=1"; then
  log_error "Failed to configure VM $VMID hardware and network"
  exit 1
fi

# GPU passthrough (if a NVIDIA device is present)
GPU_ADDR=$(lspci -d 10de: | awk 'NR==1 {print $1}')
if [[ -n "$GPU_ADDR" ]]; then
  log_info "Настройка GPU $GPU_ADDR"
  qm set "$VMID" --hostpci0 "$GPU_ADDR,pcie=1,x-vga=1"
else
  log_warn "NVIDIA GPU не найден – проброс пропущен"
fi

# Start the VM if it is not already running
if qm status "$VMID" 2>/dev/null | grep -q "running"; then
  log_info "VM $VMID уже запущена"
else
  log_info "Запуск VM $VMID"
  qm start "$VMID"
fi

# Wait for QEMU Guest Agent (static IP, DHCP not required)
log_info "Ожидание QEMU Guest Agent"
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    log_info "Guest Agent готов"
    break
  fi
  sleep 2
done

# Inside the guest: fix GPT, expand root partition, and clean multipath
qm guest exec "$VMID" -- bash -lc '
  set -e
  apt-get update -y && apt-get install -y cloud-guest-utils gdisk || true
  # Fix GPT backup table
  sgdisk -e /dev/sda
  partprobe /dev/sda
  # Expand root partition and filesystem
  growpart /dev/sda 1
  resize2fs /dev/sda1
  # Clean multipath configuration
  systemctl stop multipathd || true
  systemctl disable multipathd || true
  apt-get purge -y multipath-tools || true
  update-initramfs -u
'

log_info "VM $VMID готова. IP: $STATIC_IP"
log_info "Подключение: ssh ubuntu@$STATIC_IP"

# Update known_hosts for convenient SSH access
ssh-keygen -R "$STATIC_IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$STATIC_IP" >> "$HOME/.ssh/known_hosts"
