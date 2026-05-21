#!/usr/bin/env bash
set -e
set -euxo pipefail

VMID=110
NAME=llm-vm
STORAGE=local-lvm
TEMPLATE=9000

qm clone $TEMPLATE $VMID --name $NAME --full true

qm set $VMID \
  --memory 32768 \
  --cores 12 \
  --cpu host \
  --scsi0 ${STORAGE}:64 \
  --net0 virtio,bridge=vmbr0

qm set $VMID \
  --ciuser ubuntu \
  --sshkey ~/.ssh/id_rsa.pub \
  --ipconfig0 ip=dhcp

qm start $VMID

echo "LLM VM CREATED"