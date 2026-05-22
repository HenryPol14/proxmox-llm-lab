#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: запустите скрипт от root" >&2
  exit 1
fi

cpu_vendor=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print tolower($2)}')
required_param="intel_iommu=on"
if [[ "$cpu_vendor" == *amd* ]]; then
  required_param="amd_iommu=on"
fi

grub_file="/etc/default/grub"
current_cmdline=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" || true)
current_args=""
if [[ "$current_cmdline" =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"$ ]]; then
  current_args="${BASH_REMATCH[1]}"
fi

modules_file="/etc/modules"
missing_modules=()
for module in vfio vfio_iommu_type1 vfio_pci; do
  if ! grep -Eq "^${module}(\s|$)" "$modules_file" 2>/dev/null; then
    missing_modules+=("$module")
  fi
done

check_grub=false
if [[ "$current_args" == *"$required_param"* ]] && [[ "$current_args" == *"iommu=pt"* ]]; then
  check_grub=true
fi

if [[ "$check_grub" != true ]]; then
  updated_args=$(echo "$current_args" | sed -E 's/(intel_iommu=on|amd_iommu=on)//g; s/(^| )iommu=pt( |$)/ /g' | xargs)
  if [[ -n "$updated_args" ]]; then
    updated_args="$required_param $updated_args iommu=pt"
  else
    updated_args="$required_param iommu=pt"
  fi
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"$|GRUB_CMDLINE_LINUX_DEFAULT=\"$updated_args\"|" "$grub_file"
  echo "Updated GRUB_CMDLINE_LINUX_DEFAULT: $updated_args"
fi

if [[ ${#missing_modules[@]} -gt 0 ]]; then
  printf '%s\n' "${missing_modules[@]}" >> "$modules_file"
  echo "Added missing vfio modules to $modules_file: ${missing_modules[*]}"
fi

update-initramfs -u -k all
update-grub

echo "REBOOT REQUIRED"
