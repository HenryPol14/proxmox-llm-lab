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

## Повторный запуск скриптов

Скрипты в `scripts/` настроены так, чтобы не ломать уже существующую конфигурацию и не выполнять лишнюю работу при повторном запуске:

- `01-install-proxmox-tools.sh` — устанавливает только недостающие пакеты.
- `02-enable-iommu.sh` — обновляет GRUB только при отсутствии нужных параметров и добавляет только отсутствующие `vfio`-модули.
- `03-download-cloud-image.sh` — не скачивает образ повторно, если файл уже существует.
- `04-create-cloudinit-template.sh` — не пересоздаёт шаблон по умолчанию; для принудительного пересоздания используйте `FORCE_REBUILD=1`.
- `05-create-llm-vm.sh` — не удаляет существующую VM, обновляет конфигурацию и не перезапускает уже запущенную VM.
- `06-create-monitoring-vm.sh` — не пересоздаёт существующую VM, обновляет конфигурацию и не перезапускает уже запущенную VM.
- `07-install-docker.sh` — пропускает установку, если Docker уже установлен.
- `08-install-nvidia-toolkit.sh` — пропускает установку и конфигурацию, если `nvidia-container-toolkit` уже установлен.
- `09-deploy-ollama.sh` — не перезаписывает `docker-compose.yml`, если он уже существует.
- `10-deploy-monitoring.sh` — проверяет наличие файла compose перед запуском.
- `run-all.sh` — содержит актуальные ссылки на текущие скрипты.

## Network Validation

Run:

```bash
./scripts/11-audit-network.sh
```

Checks:
- bridges
- routing
- NAT
- nftables
- dnsmasq
- forwarding
- VM networking

## SSH-ключ для шаблона

Шаблон в `scripts/04-create-cloudinit-template.sh` хранит SSH-ключ в cloud-init и использует его для всех новых VM.

### Обновить ключ без пересоздания шаблона

```bash
./scripts/04-create-cloudinit-template.sh
```

По умолчанию скрипт использует `~/.ssh/id_rsa.pub`. Если нужен другой ключ, задайте переменную окружения:

```bash
SSH_PUBLIC_KEY=~/.ssh/my-key.pub ./scripts/04-create-cloudinit-template.sh
```

### Полностью пересоздать шаблон

```bash
FORCE_REBUILD=1 ./scripts/04-create-cloudinit-template.sh
```

Это удалит старый шаблон `9000` и создаст новый заново.

## Ручной IP и диагностика интерфейсов

Если DHCP не срабатывает сразу после создания VM, можно запускать создание в ручном режиме и проверять состояние интерфейсов в госте.

### Ручной IP для LLM VM

```bash
NETWORK_MODE=manual \
STATIC_IP=10.10.10.50 \
STATIC_PREFIX=24 \
STATIC_GATEWAY=10.10.10.1 \
STATIC_DNS=10.10.10.1 \
./scripts/05-create-llm-vm.sh
```

### Ручной IP для monitoring VM

```bash
NETWORK_MODE=manual \
STATIC_IP=10.10.10.60 \
STATIC_PREFIX=24 \
STATIC_GATEWAY=10.10.10.1 \
STATIC_DNS=10.10.10.1 \
./scripts/06-create-monitoring-vm.sh
```

### Размер дополнительного диска

Скрипт `scripts/05-create-llm-vm.sh` принимает размер второго диска в переменной `DATA_DISK_SIZE`.
Перед передачей в Proxmox значение нормализуется до числа в GiB, поэтому можно использовать либо `120`, либо `120G`.

```bash
DATA_DISK_SIZE=120G ./scripts/05-create-llm-vm.sh
```

Если передать невалидное значение, скрипт завершится с ошибкой до вызова `qm`.

### Что делает скрипт при создании VM

- пытается получить IP по DHCP;
- если IP не появился, выполняет диагностику интерфейсов в госте;
- поднимает интерфейсы, которые оказались в состоянии `DOWN`;
- выводит текущие адреса, маршруты и `cloud-init`-лог;
- если проблема остаётся, показывает диагностику хоста и текущие DHCP-lease.

### Быстрая ручная проверка в госте

После старта VM можно зайти в неё и проверить состояние интерфейса вручную:

```bash
ssh ubuntu@<ip>
ip -o link show
ip -4 -o addr show scope global
ip r
sudo ip link set ens18 up
```

Если интерфейс не поднимается, проверьте корректность bridge и dnsmasq на Proxmox хосте через `./scripts/11-audit-network.sh`.
