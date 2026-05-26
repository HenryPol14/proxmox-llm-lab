#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"

debug_init
ensure_root

install_missing_packages curl wget vim git htop jq unzip gnupg lsb-release qemu-guest-agent net-tools dnsutils pciutils usbutils zip tar

log_info "DONE"
