#!/usr/bin/env bash
# 02-enable-iommu.sh – включение IOMMU и загрузка VFIO‑модулей
# Идемпотентный скрипт: параметры добавляются только при необходимости, повторный запуск безопасен
# Добавляем вызов debug_init для включения трассировки при DEBUG=1
# 02-enable-iommu.sh – включение и настройка IOMMU на Proxmox хосте
# Скрипт определяет тип процессора, добавляет нужный параметр в GRUB и загружает VFIO‑модули
# Идемпотентен: при повторном запуске параметры добавляются только если их нет
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
debug_init
ensure_root

cpu_vendor=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print tolower($2)}')
required_param="intel_iommu=on"
if [[ "$cpu_vendor" == *amd* ]]; then
  required_param="amd_iommu=on"
fi

# Update GRUB command line idempotently
update_grub_cmdline "$required_param"

# Ensure required VFIO modules are present
for module in vfio vfio_iommu_type1 vfio_pci; do
  ensure_line_in_file "$module" "/etc/modules"
done

log_info "REBOOT REQUIRED"

