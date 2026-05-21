#!/usr/bin/env bash
set -euo pipefail

# Description: Create a Proxmox VM and convert it to a cloud-init template.
# Usage: sudo scripts/04-create-cloudinit-template.sh
# Note: Adjust VMID, STORAGE and IMG variables as needed.

VMID=9000
STORAGE=SSD-VMs
IMG=/var/lib/vz/template/qcow2/ubuntu-26.04.img

qm destroy "$VMID" --purge || true

qm create "$VMID" \
  --name ubuntu-26-template \
  --memory 4096 \
  --cores 4 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr0

qm set "$VMID" --efidisk0 "${STORAGE}:1"
qm importdisk "$VMID" "$IMG" "$STORAGE"

IMPORT_DISK=$(qm config "$VMID" | awk '/unused0/ { split($2, a, ","); print a[1] }')

qm set "$VMID" \
  --scsihw virtio-scsi-single \
  --scsi0 "${IMPORT_DISK}",discard=on,ssd=1,iothread=1

qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0

qm set "$VMID" \
  --serial0 socket \
  --vga serial0

qm set "$VMID" --agent enabled=1
qm template "$VMID"

echo "TEMPLATE CREATED"

