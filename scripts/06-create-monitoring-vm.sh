#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Идентификатор и имя создаваемой VM.
VMID=120
NAME="monitoring-vm"
# Хранилище и шаблон, от которого будет клонироваться VM.
STORAGE="SSD-VMs"
TEMPLATE=9000
NETWORK_MODE="${NETWORK_MODE:-manual}"
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
  --net0 virtio,bridge=vmbr1

# Включаем cloud-init и используем настройки шаблона.
qm set "$VMID" \
  --ciuser ubuntu \
  --ipconfig0 "$IPCONFIG0"

# Запускаем VM после завершения конфигурации, если она еще не работает.
if qm status "$VMID" 2>/dev/null | grep -q 'running'; then
  echo "VM $VMID уже запущена."
else
  qm start "$VMID"
fi

echo "MONITORING VM CREATED"
