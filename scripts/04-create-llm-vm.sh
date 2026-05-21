#!/usr/bin/env bash
set -euo pipefail

# Description: Clone the cloud-init template and configure an LLM VM.
# Usage: sudo scripts/04-create-llm-vm.sh
# Note: Review `VMID`, `NAME`, `STORAGE` and `TEMPLATE` variables.

VMID=110
NAME=llm-vm
STORAGE=SSD-VMs
TEMPLATE=9000

qm destroy "$VMID" --purge || true
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full true

qm set "$VMID" \
  --memory 24576 \
  --cores 4 \
  --cpu host \
  --balloon 0 \
  --numa 1

qm set "$VMID" \
  --machine q35 \
  --bios ovmf

qm set "$VMID" \
  --scsi0 "${STORAGE}:60",discard=on,ssd=1,iothread=1

qm set "$VMID" \
  --scsi1 "${STORAGE}:120",discard=on,ssd=1,iothread=1

qm set "$VMID" \
  --net0 virtio,bridge=vmbr0

qm set "$VMID" \
  --ciuser ubuntu \
  --ipconfig0 ip=dhcp

qm set "$VMID" --agent enabled=1
qm set "$VMID" \
  --hostpci0 01:00.0,pcie=1,rombar=0
qm set "$VMID" --hostpci1 01:00.1
qm set "$VMID" --vga none

qm start "$VMID"

echo "LLM VM CREATED"

