#!/usr/bin/env bash
set -e
set -euxo pipefail

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