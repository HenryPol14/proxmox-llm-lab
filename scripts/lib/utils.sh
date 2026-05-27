#!/usr/bin/env bash
# utils.sh – вспомогательные функции для скриптов проекта Proxmox LLM Lab
# Этот файл предоставляет общие утилиты: от инициализации отладки до установки пакетов
# Все функции задокументированы на русском языке для удобства поддержки

set -euo pipefail

# Инициализация отладки, если задана переменная DEBUG
# При включённом режиме вывод команд будет трассироваться (set -x) и записываться в лог файл
debug_init() {
  if [[ -n "${DEBUG:-}" ]]; then
    set -x
    local log_file="/var/log/proxmox-$(basename "${BASH_SOURCE[0]}").log"
    exec > >(tee -a "$log_file") 2>&1
    log_info "Debug mode enabled – logging to $log_file"
  fi
}

# Глобальный обработчик ошибок – фиксирует код завершения и номер строки, где произошла ошибка
error_trap() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-?}
  log_error "Script aborted with exit code $exit_code at line $line_no"
}
trap error_trap ERR

# Функции логирования с меткой времени
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_info()  { log "INFO: $*"; }
log_warn()  { log "WARN: $*"; }
log_error() { log "ERROR: $*" >&2; }

# Проверка запуска скрипта от имени root; при отсутствии прав скрипт завершится с ошибкой
ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Run script as root"
    exit 1
  fi
}

# Установка недостающих пакетов через apt (идемпотентно)
# Принимает список пакетов, проверяет их наличие и устанавливает только отсутствующие
install_missing_packages() {
  local packages=("$@")
  local missing=()
  for pkg in "${packages[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if (( ${#missing[@]} )); then
    log_info "Installing missing packages: ${missing[*]}"
    apt-get update -y
    apt-get install -y "${missing[@]}"
  else
    log_info "All required packages are already installed"
  fi
}

# Убедиться, что в указанном файле присутствует строка (например, в /etc/modules)
ensure_line_in_file() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# Обновление параметров GRUB_CMDLINE_LINUX_DEFAULT (идемпотентно)
# Добавляет требуемый параметр и включаемый режим iommu=pt, удаляя дубликаты
update_grub_cmdline() {
  local required_param="$1"
  local grub_file="/etc/default/grub"
  local current=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" || true)
  local args=""
  if [[ $current =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"$ ]]; then
    args="${BASH_REMATCH[1]}"
  fi
  # Удаляем существующие параметры iommu
  args=$(echo "$args" | sed -E 's/(intel_iommu=on|amd_iommu=on)//g; s/(^| )iommu=pt( |$)/ /g' | xargs)
  # Добавляем необходимые параметры
  if [[ -n $args ]]; then
    args="$required_param $args iommu=pt"
  else
    args="$required_param iommu=pt"
  fi
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*$|GRUB_CMDLINE_LINUX_DEFAULT=\"$args\"|" "$grub_file"
  log_info "Updated GRUB cmdline: $args"
  update-initramfs -u -k all
  update-grub
}
