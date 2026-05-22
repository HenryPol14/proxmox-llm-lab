#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Включает IOMMU и настраивает модули VFIO для PCI passthrough.
# Использование: sudo scripts/02-enable-iommu.sh
# Примечание: После выполнения требуется перезагрузка.

# Печатаем IOMMU-группы и устройства, чтобы пользователь видел текущее состояние PCI.
for g in /sys/kernel/iommu_groups/*; do
    echo "IOMMU Group ${g##*/}:"
    for d in "$g"/devices/*; do
        lspci -nns "${d##*/}"
    done
    echo
done

# Определяем производителя CPU, чтобы выбрать правильный параметр для загрузчика.
cpu_vendor=$(lscpu | awk -F: '/Vendor ID/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print tolower($2)}')
required_param="intel_iommu=on"
if [[ "$cpu_vendor" == *amd* ]]; then
    required_param="amd_iommu=on"
fi

# Смотрим текущую строку параметров GRUB.
grub_file="/etc/default/grub"
current_cmdline=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" || true)
current_args=""
if [[ "$current_cmdline" =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"$ ]]; then
    current_args="${BASH_REMATCH[1]}"
fi

check_grub=false
if [[ "$current_args" == *"$required_param"* ]] && [[ "$current_args" == *"iommu=pt"* ]]; then
    check_grub=true
fi

# Проверяем, какие модули VFIO уже заданы в /etc/modules.
modules_file="/etc/modules"
missing_modules=()
for module in vfio vfio_iommu_type1 vfio_pci; do
    if ! grep -Eq "^${module}(\s|$)" "$modules_file" 2>/dev/null; then
        missing_modules+=("$module")
    fi
done

# Если всё уже настроено, выходим без изменений.
if [[ "$check_grub" == true ]] && [[ ${#missing_modules[@]} -eq 0 ]]; then
    echo "IOMMU already enabled and vfio modules already configured. No changes needed."
    exit 0
fi

# Если нужно, обновляем строку загрузчика GRUB.
if [[ "$check_grub" != true ]]; then
    updated_args="$current_args"
    updated_args=$(echo "$updated_args" | sed -E 's/(intel_iommu=on|amd_iommu=on)//g')
    updated_args=$(echo "$updated_args" | sed -E 's/(^| )iommu=pt( |$)/ /g')
    updated_args=$(echo "$updated_args" | xargs)
    if [[ -n "$updated_args" ]]; then
        updated_args="$required_param $updated_args iommu=pt"
    else
        updated_args="$required_param iommu=pt"
    fi

    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"$|GRUB_CMDLINE_LINUX_DEFAULT=\"$updated_args\"|" "$grub_file"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$updated_args\"" >> "$grub_file"
    fi
    echo "Updated GRUB_CMDLINE_LINUX_DEFAULT: $updated_args"
fi

# Добавляем недостающие модули VFIO в /etc/modules.
if [[ ${#missing_modules[@]} -gt 0 ]]; then
    printf '%s\n' "${missing_modules[@]}" >> "$modules_file"
    echo "Added missing vfio modules to $modules_file: ${missing_modules[*]}"
fi

# Пересобираем initramfs и обновляем GRUB.
update-initramfs -u -k all
update-grub

echo "REBOOT REQUIRED"
