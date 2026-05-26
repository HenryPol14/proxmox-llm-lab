#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
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

