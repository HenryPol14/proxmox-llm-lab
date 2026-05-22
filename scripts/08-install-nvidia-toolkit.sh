#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Устанавливает NVIDIA Container Toolkit и настраивает Docker runtime.
# Использование: sudo scripts/08-install-nvidia-toolkit.sh
# Примечание: Требует наличия NVIDIA-драйверов и GPU на хосте.

# Добавляем ключ подписи репозитория NVIDIA.
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Добавляем репозиторий NVIDIA Container Toolkit.
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Обновляем индексы пакетов и устанавливаем toolkit.
apt update
apt install -y nvidia-container-toolkit

# Конфигурируем runtime для Docker.
nvidia-ctk runtime configure --runtime=docker

# Перезапускаем Docker, чтобы применить настройки.
systemctl restart docker

# Проверяем работоспособность NVIDIA в контейнере.
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
