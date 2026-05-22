#!/usr/bin/env bash

set -e

./01-install-proxmox-tools.sh
./02-enable-iommu.sh
./03-download-cloud-image.sh
./04-create-cloudinit-template.sh
./05-create-llm-vm.sh
./06-create-monitoring-vm.sh
