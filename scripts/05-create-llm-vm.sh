#!/usr/bin/env bash
set -euo pipefail

# Конфигурация
VMID=${1:-110}
NAME="llm-server"
TEMPLATE=9000
STORAGE="SSD-VMs"
GPU_ADDR=$(lspci -d 10de: | cut -d' ' -f1 | head -n 1) # Авто-поиск первой карты NVIDIA

# Проверка на root
[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

echo "--- Recreating VM $VMID ---"
qm destroy "$VMID" --purge 2>/dev/null || true

# 1. Клонирование (Linked clone быстрее, если не планируете удалять шаблон)
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

# 2. Настройка ресурсов (оптимизация под LLM)
qm set "$VMID" \
  --memory 20480 \
  --balloon 0 \
  --numa 1 \
  --cores 4 \
  --cpu host,flags=+aes \
  --agent enabled=1

# 3. Диски
# Расширяем основной диск (который пришел из шаблона) вместо пересоздания
qm resize "$VMID" scsi0 +40G 

# Добавляем второй диск для моделей
qm set "$VMID" --scsi1 "${STORAGE}:120",discard=on,ssd=1,iothread=1

# 4. Проброс GPU (с проверкой)
if [ -n "$GPU_ADDR" ]; then
  echo "Found GPU at $GPU_ADDR"
  # Пробрасываем основное устройство и аудио-функцию (обычно .1)
  qm set "$VMID" --hostpci0 "${GPU_ADDR%.*},pcie=1,x-vga=1"
else
  echo "WARNING: NVIDIA GPU not found!"
fi

# 5. Сеть и Cloud-init
qm set "$VMID" \
  --net0 virtio,bridge=vmbr1 \
  --ciuser ubuntu \
  --cipassword "ubuntu" \
  --ipconfig0 ip=dhcp \
  --sshkeys ~/.ssh/id_rsa.pub # Авто-добавление ключа

# 6. Запуск
echo "Starting VM..."
qm start "$VMID"

echo "DONE. IP will be assigned via DHCP."

# Ожидание готовности Guest Agent
echo "Waiting for Guest Agent to start..."
until qm guest exec "$VMID" -- uptime >/dev/null 2>&1; do
  sleep 2
done

echo "Installing NVIDIA Drivers and Docker..."

# Команды для выполнения внутри ВМ
qm guest exec "$VMID" -- bash -c "
  # 1. Обновление и установка базовых зависимостей
  apt-get update && apt-get install -y curl gnupg2 software-properties-common

  # 2. Установка драйверов NVIDIA (headless версия для серверов)
  apt-get install -y nvidia-driver-535-server nvidia-utils-535-server

  # 3. Установка Docker
  curl -fsSL https://docker.com -o get-docker.sh
  sh get-docker.sh

  # 4. Установка NVIDIA Container Toolkit
  curl -fsSL https://github.io | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://github.io | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  
  apt-get update && apt-get install -y nvidia-container-toolkit

  # 5. Настройка Docker для использования NVIDIA Runtime
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
"

echo "Installation complete. Checking GPU inside VM:"
qm guest exec "$VMID" -- nvidia-smi
