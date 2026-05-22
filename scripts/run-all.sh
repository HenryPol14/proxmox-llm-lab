#!/usr/bin/env bash

set -e

# Подготовка Proxmox хоста.
./01-install-proxmox-tools.sh
./02-enable-iommu.sh

# Загрузка и подготовка базового Ubuntu образа.
./03-download-cloud-image.sh
./04-create-cloudinit-template.sh

# Создание и настройка LLM VM.
./05-create-llm-vm.sh

# Создание отдельной VM для мониторинга.
./06-create-monitoring-vm.sh
