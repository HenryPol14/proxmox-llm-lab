#!/usr/bin/env bash
set -e
set -euxo pipefail

VMID=9000
STORAGE=local-lvm
IMG=/var/lib/vz/template/qcow2/ubuntu-26.04.img

qm destroy $VMID --purge 2>/dev/null || true

qm create $VMID \
  --name ubuntu-26-template \
  --memory 4096 \
  --cores 4 \
  --net0 virtio,bridge=vmbr0

qm importdisk $VMID $IMG $STORAGE

qm set $VMID \
  --scsihw virtio-scsi-pci \
  --scsi0 ${STORAGE}:vm-${VMID}-disk-0

qm set $VMID --ide2 ${STORAGE}:cloudinit
qm set $VMID --boot c --bootdisk scsi0

qm set $VMID --serial0 socket --vga serial0
qm set $VMID --agent enabled=1

qm template $VMID

echo "TEMPLATE CREATED"