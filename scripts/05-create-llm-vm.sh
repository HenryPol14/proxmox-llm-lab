#!/usr/bin/env bash
set -euo pipefail

VMID=${1:-110}
NAME="llm-server"
TEMPLATE=9000
STORAGE="SSD-VMs"
MEM=20480
CORES=4
SYS_DISK_SIZE="44G"
DATA_DISK_SIZE="120G"
NETWORK_MODE="${NETWORK_MODE:-dhcp}"
STATIC_IP="${STATIC_IP:-}"
STATIC_PREFIX="${STATIC_PREFIX:-24}"
STATIC_GATEWAY="${STATIC_GATEWAY:-}"
STATIC_DNS="${STATIC_DNS:-}"

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
    normalized_ip="${normalized_ip}/${STATIC_PREFIX}"
  fi

  if [[ -n "$STATIC_DNS" ]]; then
    echo "ip=${normalized_ip},gw=${STATIC_GATEWAY},dns=${STATIC_DNS}"
  else
    echo "ip=${normalized_ip},gw=${STATIC_GATEWAY}"
  fi
}

ensure_guest_interfaces_up() {
  qm guest exec "$VMID" -- bash -lc 'set +e
printf "\n== Состояние интерфейсов до коррекции ==\n"
ip -o link show
for iface in $(ip -o link show | cut -d" " -f2 | cut -d: -f1); do
  state=$(cat /sys/class/net/${iface}/operstate 2>/dev/null || echo unknown)
  if [[ "$state" != "up" ]]; then
    echo "Поднимаю интерфейс ${iface} (state=$state)"
    ip link set "$iface" up
  fi
done
printf "\n== Состояние интерфейсов после коррекции ==\n"
ip -o link show
'
}

print_guest_network_diagnostics() {
  qm guest exec "$VMID" -- bash -lc 'set +e
printf "\n== Интерфейсы ==\n"
ip -o link show || true
printf "\n== Адреса ==\n"
ip -4 -o addr show scope global || true
printf "\n== Маршруты ==\n"
ip r || true
printf "\n== Cloud-init ==\n"
cloud-init status --long 2>/dev/null || true
cat /var/log/cloud-init.log 2>/dev/null | tail -n 50 || true
' 2>/dev/null || true
}

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

if ! command -v qm >/dev/null 2>&1; then
  echo "ERROR: qm не найден. Запустите на Proxmox хосте." >&2
  exit 1
fi

if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  echo "ERROR: Шаблон VM $TEMPLATE не найден." >&2
  exit 1
fi

IPCONFIG0=$(build_ipconfig0)

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

qm set "$VMID" \
  --ostype l26 \
  --memory "$MEM" \
  --cores "$CORES" \
  --cpu host \
  --balloon 0 \
  --numa 1 \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr1,queues=8 \
  --ciuser ubuntu \
  --ipconfig0 "$IPCONFIG0"

GPU_ADDR=$(lspci -d 10de: | awk 'NR==1 {print $1}')
if [[ -n "$GPU_ADDR" ]]; then
  echo "=== Настройка GPU $GPU_ADDR ==="
  qm set "$VMID" --hostpci0 "$GPU_ADDR,pcie=1,x-vga=1"
else
  echo "WARN: NVIDIA GPU не обнаружена. Проброс не выполнен."
fi

qm resize "$VMID" scsi0 "$SYS_DISK_SIZE" || true
qm set "$VMID" --scsi1 "${STORAGE}:${DATA_DISK_SIZE}",discard=on,ssd=1,iothread=1

# Включаем автозапуск VM и запоминаем MAC адрес сетевого интерфейса.
# MAC нужен для поиска точного DHCP lease на хосте.
qm set "$VMID" --onboot 1
VM_MAC=$(qm config "$VMID" | grep -oE 'virtio=[0-9A-Fa-f:]{17}' | head -n1 | cut -d= -f2 || true)

if qm status "$VMID" 2>/dev/null | grep -q 'running'; then
  echo "VM $VMID уже запущена."
else
  qm start "$VMID"
fi

echo "=== Ожидание QEMU Guest Agent ==="
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    echo "Guest Agent готов."
    break
  fi
  echo "Ожидание guest agent... ($i/30)"
  sleep 2
  if [[ $i -eq 30 ]]; then
    echo "ERROR: Guest Agent не поднялся." >&2
    exit 1
  fi
done

echo "=== Анализ сети гостя ==="
ensure_guest_interfaces_up
print_guest_network_diagnostics

echo "=== Настройка гостевой ОС ==="
qm guest exec "$VMID" -- bash -lc "set -e
apt-get update
apt-get install -y curl gnupg lsb-release
curl -fsSL https://get.docker.com | sh
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
distribution=\"\$(. /etc/os-release; echo \$ID\$VERSION_ID)\"
url=\"https://nvidia.github.io/libnvidia-container/ubuntu\${distribution}/nvidia-container-toolkit.list\"
curl -s -L \"\$url\" | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker"

echo "=== Ждем IP адрес ==="
IP_ADDR=""
for i in {1..12}; do
  IP_ADDR=$(qm guest exec "$VMID" -- bash -lc "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | grep -v '^127\.' | head -n1" 2>/dev/null || true)
  if [[ -n "$IP_ADDR" ]]; then
    break
  fi
  echo "Ожидание DHCP... ($((i*5))s)"
  sleep 5
done

if [[ -n "$IP_ADDR" ]]; then
  echo "=== VM готова ==="
  echo "IP адрес: $IP_ADDR"
  echo "Подключение: ssh ubuntu@$IP_ADDR"
else
  echo "ERROR: IP адрес не получен за 60 секунд." >&2
  echo "Проверьте следующие пункты:" >&2
  echo "1. DHCP доступен на мосте vmbr1." >&2
  echo "2. Внутри VM запущен cloud-init / guest agent." >&2
  echo "3. Нет блокировки трафика на хосте или в firewall." >&2

  echo "--- Диагностика хоста ---" >&2
  if ip link show vmbr1 >/dev/null 2>&1; then
    echo "vmbr1 существует"
  else
    echo "vmbr1 не найден"
  fi
  if pgrep -a dnsmasq >/dev/null 2>&1; then
    echo "dnsmasq запущен"
    pgrep -a dnsmasq
  else
    echo "dnsmasq не запущен"
  fi

  lease_match=""
  if [[ -f /var/lib/misc/dnsmasq.leases && -n "$VM_MAC" ]]; then
    lease_match=$(grep -i "$VM_MAC" /var/lib/misc/dnsmasq.leases || true)
  fi

  if [[ -z "$lease_match" ]]; then
    echo "Причина 1: DHCP lease для этой VM не найден."
    echo "Симптом: DHCP на host не выдал адрес этой VM."
  else
    echo "Причина 1: DHCP lease для этой VM найден."
    echo "Причина 2: IP не появился в guest или guest не поднял сеть."
  fi

  if [[ -f /var/lib/misc/dnsmasq.leases ]]; then
    echo "--- DHCP leases ---"
    tail -n 20 /var/lib/misc/dnsmasq.leases || true
    if [[ -n "$VM_MAC" ]]; then
      echo "--- Lease для MAC $VM_MAC ---"
      echo "$lease_match"
    fi
  else
    echo "dnsmasq.leases не найден"
  fi

  nft list ruleset 2>/dev/null | sed -n '1,80p' || true

  echo "--- Диагностика гостевой ОС ---" >&2
  print_guest_network_diagnostics

  if [[ -n "$lease_match" ]]; then
    echo "Причина 3: guest не получил IP несмотря на lease. Проверьте cloud-init, guest agent и интерфейс в guest." >&2
  else
    echo "Причина 3: DHCP не выдал lease для этой VM. Проверьте dnsmasq, bridge vmbr1 и firewall." >&2
  fi
  exit 1
fi
