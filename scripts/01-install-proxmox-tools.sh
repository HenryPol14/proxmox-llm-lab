#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

packages=(curl wget vim git htop jq unzip gnupg lsb-release qemu-guest-agent net-tools dnsutils pciutils usbutils zip tar)
missing_packages=()

for pkg in "${packages[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_packages+=("$pkg")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  apt update
  apt install -y "${missing_packages[@]}"
  echo "Установлены недостающие пакеты: ${missing_packages[*]}"
else
  echo "Все необходимые пакеты уже установлены. Пропускаю apt install."
fi

echo "DONE"
