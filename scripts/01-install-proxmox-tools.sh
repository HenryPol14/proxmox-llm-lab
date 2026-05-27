#!/usr/bin/env bash
# 01-install-proxmox-tools.sh – установка базовых утилит на Proxmox хост
# Скрипт использует utils.sh для логирования, отладки и идемпотентной установки пакетов
# При повторном запуске устанавливает только недостающие пакеты, не меняя уже существующие
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"

debug_init
ensure_root

install_missing_packages curl wget vim git htop jq unzip gnupg lsb-release qemu-guest-agent net-tools dnsutils pciutils usbutils zip tar

log_info "DONE"
