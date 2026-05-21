#!/usr/bin/env bash
set -e
set -euxo pipefail

# Description: Download Ubuntu cloud image for creating templates.
# Usage: sudo scripts/02-download-cloud-image.sh
# Note: Stores image at /var/lib/vz/template/qcow2

mkdir -p /var/lib/vz/template/qcow2
cd /var/lib/vz/template/qcow2

wget -O ubuntu-26.04.img \
https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img

echo "IMAGE DOWNLOADED"
