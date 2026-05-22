#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Клонирует cloud-init шаблон Proxmox и настраивает LLM VM с GPU passthrough.
# Использование: sudo scripts/05-create-llm-vm.sh [VMID]
# Примечание: Требует доступного шаблона 9000 и хранилища SSD-VMs.

VMID=${1:-110}
NAME="llm-server"
TEMPLATE=9000
STORAGE="SSD-VMs"
MEM=20480
CORES=4
SYS_DISK_SIZE="44G"
DATA_DISK_SIZE="120G"

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

if ! command -v qm >/dev/null 2>&1; then
  echo "ERROR: qm не найден. Запустите на Proxmox хосте." >&2
  exit 1
fi

# Проверка существования шаблона.
if ! qm config "$TEMPLATE" >/dev/null 2>&1; then
  echo "ERROR: Шаблон VM $TEMPLATE не найден." >&2
  exit 1
fi

# 1. Удаляем старую VM при необходимости.
echo "=== Создаем или пересоздаем VM $VMID ==="
qm destroy "$VMID" --purge 2>/dev/null || true
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

# 2. Конфигурация ресурсов VM.
echo "=== Настройка ресурсов VM ==="
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
  --cipassword ubuntu \
  --ipconfig0 ip=dhcp

# 3. Проброс GPU.
GPU_ADDR=$(lspci -d 10de: | awk 'NR==1 {print $1}')
if [[ -n "$GPU_ADDR" ]]; then
  echo "=== Настройка проброса GPU $GPU_ADDR ==="
  qm set "$VMID" --hostpci0 "$GPU_ADDR,pcie=1,x-vga=1"
else
  echo "WARN: NVIDIA GPU не обнаружена. Проброс не выполнен."
fi

# 4. Диски VM.
echo "=== Настройка дисков ==="
qm resize "$VMID" scsi0 "$SYS_DISK_SIZE" || true
qm set "$VMID" --scsi1 "${STORAGE}:${DATA_DISK_SIZE}",discard=on,ssd=1,iothread=1

# 5. Запуск VM и ожидание гостевого агента.
echo "=== Запуск VM ==="
qm start "$VMID"

# Включаем автозагрузку VM.
qm set "$VMID" --onboot 1

echo "=== Ожидание QEMU Guest Agent ==="
for i in {1..30}; do
  if qm guest exec "$VMID" -- uptime >/dev/null 2>&1; then
    echo "Guest Agent готов."
    break
  fi
  echo "Ожидание guest agent... ($i/30)"
  sleep 2
done


# 6. Выполняем базовую настройку внутри гостевой ОС.
echo "=== Настройка гостевой ОС ==="
qm guest exec "$VMID" -- bash -lc "set -e
apt-get update
apt-get install -y curl gnupg lsb-release
# Установка Docker
curl -fsSL https://get.docker.com | sh
# Добавление NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
distribution=\"\$(. /etc/os-release; echo \$ID\$VERSION_ID)\"
url=\"https://nvidia.github.io/libnvidia-container/ubuntu\${distribution}/nvidia-container-toolkit.list\"
curl -s -L \"\$url\" | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker"

# 7. Ожидание сетевого IP.
echo "=== Ждем IP адрес гостевой ОС ==="
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
  echo "WARNING: IP адрес не получен. Проверьте DHCP и мост vmbr1."
fi
