#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Clone the cloud-init template and configure an LLM VM.
# Usage: sudo scripts/04-create-llm-vm.sh
# Note: Review \\`VMID\\`, \\`NAME\\`, \\`STORAGE\\` and \\`TEMPLATE\\` variables.

VMID=110
NAME=llm-vm
STORAGE=SSD-VMs
TEMPLATE=9000

qm clone $TEMPLATE $VMID --name $NAME --full true

qm set $VMID \
  --memory 24576 \
  --cores 4 \
  --cpu host \
  --balloon 0 \
  --numa 1 \
  --scsi0 ${STORAGE}:60 \
  --scsi1 ${STORAGE}:120,discard=on,ssd=1,iothread=1 \
  --net0 virtio,bridge=vmbr0 \
  --ciuser ubuntu \
  --ipconfig0 ip=dhcp \
  --agent enabled=1 \
  --machine q35 \
  --hostpci0 01:00,pcie=1,x-vga=1

qm start $VMID

echo "LLM VM CREATED"
