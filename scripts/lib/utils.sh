#!/usr/bin/env bash
set -euo pipefail

# Initialize debugging if DEBUG is set
debug_init() {
  if [[ -n "${DEBUG:-}" ]]; then
    # Enable command tracing
    set -x
    # Redirect all output to a log file for later analysis
    local log_file="/var/log/proxmox-$(basename "${BASH_SOURCE[0]}").log"
    exec > >(tee -a "$log_file") 2>&1
    log_info "Debug mode enabled – logging to $log_file"
  fi
}

# Global error trap to capture failures
error_trap() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-?}
  log_error "Script aborted with exit code $exit_code at line $line_no"
}
trap error_trap ERR

# Logging helpers with timestamps
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_info()  { log "INFO: $*"; }
log_warn()  { log "WARN: $*"; }
log_error() { log "ERROR: $*" >&2; }

# Ensure script runs as root
ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Run script as root"
    exit 1
  fi
}

# Install missing apt packages (idempotent)
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

# Ensure a line exists in a file (e.g., /etc/modules)
ensure_line_in_file() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# Update GRUB cmdline idempotently
update_grub_cmdline() {
  local required_param="$1"
  local grub_file="/etc/default/grub"
  local current=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file" || true)
  local args=""
  if [[ $current =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"$ ]]; then
    args="${BASH_REMATCH[1]}"
  fi
  # Remove existing iommu params
  args=$(echo "$args" | sed -E 's/(intel_iommu=on|amd_iommu=on)//g; s/(^| )iommu=pt( |$)/ /g' | xargs)
  # Add required params
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
