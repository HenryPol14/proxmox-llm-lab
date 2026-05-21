#!/usr/bin/env bash
set -euxo pipefail

# Description: Install NVIDIA container toolkit and configure Docker runtime.
# Usage: sudo scripts/08-install-nvidia-toolkit.sh
# Note: Requires NVIDIA drivers and GPU hardware present.

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update

apt install -y nvidia-container-toolkit

nvidia-ctk runtime configure --runtime=docker

systemctl restart docker

docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi