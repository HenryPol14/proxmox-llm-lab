#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Enable IOMMU and add vfio modules for PCI passthrough.
# Usage: sudo scripts/06-enable-iommu.sh
# Note: Requires reboot after running.

CPU_VENDOR=$(lscpu | grep Vendor)

if echo "$CPU_VENDOR" | grep -qi intel; then
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt /' /etc/default/grub
else
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt /' /etc/default/grub
fi

cat <<EOF >> /etc/modules

vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF

update-initramfs -u -k all
update-grub

echo "REBOOT REQUIRED"