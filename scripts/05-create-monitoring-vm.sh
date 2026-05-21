#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Clone the cloud-init template and configure a monitoring VM.
# Usage: sudo scripts/05-create-monitoring-vm.sh
# Note: Review `VMID`, `NAME`, `STORAGE` and `TEMPLATE` variables.

VMID=120
NAME=monitoring-vm
STORAGE=local-lvm
TEMPLATE=9000

qm clone $TEMPLATE $VMID --name $NAME --full true

qm set $VMID \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --scsi0 ${STORAGE}:32 \
  --net0 virtio,bridge=vmbr0

qm set $VMID \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=dhcp

qm start $VMID

echo "MONITORING VM CREATED"