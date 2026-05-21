Подготовка и развертывание ВМ с пробросом GPU для LLM с мониторингом

# Proxmox LLM Lab
Infrastructure for:
- LLM VM
- Grafana VM
- Docker
- GPU passthrough
- Monitoring
## Stack
- Proxmox
- Ubuntu Cloud Init
- Docker
- Ollama
- Open WebUI
- Grafana
- Prometheus

Структура
proxmox-llm-lab/
├── scripts/
│   ├── 01-install-proxmox-tools.sh
│   ├── 02-enable-iommu.sh
│   ├── 03-download-cloud-image.sh
│   ├── 04-create-cloudinit-template.sh
│   ├── 05-create-llm-vm.sh
│   ├── 06-create-monitoring-vm.sh
│   ├── 07-install-docker.sh
│   ├── 08-install-nvidia-toolkit.sh
│   ├── 09-deploy-ollama.sh
│   └── 10-deploy-monitoring.sh
│
├── docker/
│   ├── llm/
│   └── monitoring/
│
└── docs/

Workflow
VS Code
   ↓
Git repo
   ↓
GitHub
   ↓
Proxmox scripts
   ↓
Terraform/Ansible later