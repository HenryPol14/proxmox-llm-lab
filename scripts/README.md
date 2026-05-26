# Документация скриптов

## Общая информация

В каталоге `scripts/` все скрипты теперь используют общую библиотеку утилит `scripts/lib/utils.sh`. Эта библиотека предоставляет:

- **log_info**, **log_warn**, **log_error** – функции логирования с тайм‑стампом.
- **ensure_root** – проверка, что скрипт запущен от пользователя `root`.
- **install_missing_packages** – идемпотентная установка недостающих пакетов через `apt`.
- **ensure_line_in_file** – добавить строку в файл только если её ещё нет (например, в `/etc/modules`).
- **update_grub_cmdline** – модификация параметров GRUB без дублирования.

Каждый скрипт начинается с подключения утилит и вызова `ensure_root`:
```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root
```

## Как использовать утилиты
- Вместо прямых `echo`‑сообщений используйте `log_info`, `log_warn` или `log_error`.
- Для установки пакетов замените вручную написанные проверки на `install_missing_packages <list>`.
- При необходимости добавить строку в конфигурационный файл используйте `ensure_line_in_file "<строка>" "/path/to/file"`.
- Обновление параметров GRUB делается через `update_grub_cmdline "<required_param>"`.

## Описание скриптов

### 01‑install-proxmox-tools.sh
- Устанавливает набор пакетов, необходимых для дальнейшей работы, используя `install_missing_packages`.
- Выводит сообщение о завершении через `log_info`.

### 02‑enable-iommu.sh
- Определяет тип процессора (Intel/AMD) и формирует требуемый параметр `iommu`.
- Обновляет строку `GRUB_CMDLINE_LINUX_DEFAULT` через `update_grub_cmdline`.
- Добавляет модули `vfio`, `vfio_iommu_type1`, `vfio_pci` в `/etc/modules` через `ensure_line_in_file`.
- Информирует о необходимости перезагрузки.

### 03‑download-cloud-image.sh
- Скачивает образ Ubuntu 26.04, если он отсутствует.
- Сообщения о пропуске загрузки и завершении операции выводятся через `log_info`.

### 04‑create-cloudinit-template.sh
- Создаёт шаблон Cloud‑Init, проверяя наличие образа и SSH‑ключа.
- При ошибках использует `log_error`.
- Выполняет `virt-customize` для установки гостевого агента и настройки GRUB.
- При повторном запуске обновляет только SSH‑ключ, если шаблон уже существует.

### 05‑create-llm-vm.sh
- После создания VM **не** запускает установку Docker, NVIDIA‑toolkit и Ollama. Эти действия теперь вынесены в отдельные скрипты `07-install-docker.sh`, `08-install-nvidia-toolkit.sh` и `09-deploy-ollama.sh`. Их следует выполнять **внутри** созданной VM (через SSH) после её запуска.
- Выводит статус выполнения через `log_info`/`log_warn`/`log_error`.


### 06‑create-monitoring-vm.sh
- Аналогично `05-create-llm-vm.sh`, но создаёт отдельную VM для мониторинга.
- Использует общие функции для проверки сети и конфигурации.

### 07‑install-docker.sh
- Устанавливает Docker, если он не найден, и добавляет текущего пользователя в группу `docker`.
- При наличии Docker выводит сообщение через `log_info`.

### 08‑install-nvidia-toolkit.sh
- Устанавливает `nvidia-container-toolkit` и перезапускает Docker.
- Проверяет работу NVIDIA runtime и логирует результат.

### 09‑deploy-ollama.sh
- Развёртывает стек Ollama и Open‑WebUI с помощью Docker‑Compose в `/opt/llm-stack`.
- Ошибки Docker проверяются через `log_error`.

### 10‑deploy-monitoring.sh
- Запускает мониторинговый стек из `docker/monitoring/docker-compose.yml`.
- При отсутствии Docker или файла `docker-compose.yml` пишет ошибку через `log_error`.

### 11‑audit-network.sh
- Скрипт аудита сети (только чтение). Оставлен без изменения, так как он лишь выводит информацию.

## Запуск всего процесса
```bash
./run-all.sh
```
Последовательно выполняет все подготовительные шаги. Вывод будет единообразным и снабжён метками времени.

## Добавление новых скриптов
1. Добавьте в начало файла строки подключения утилит и `ensure_root`.
2. При необходимости используйте функции из `utils.sh` вместо дублирования кода.
3. Документируйте каждую новую функцию в `README.md`.

---
*Документация поддерживается в актуальном состоянии при каждом изменении скриптов.*

All scripts in the **scripts/** directory now share a common utility library located at `scripts/lib/utils.sh`.  The library provides:

- Timestamped logging helpers: `log_info`, `log_warn`, `log_error`.
- `ensure_root` – aborts if the script is not executed as root.
- `install_missing_packages` – idempotent APT package installation.
- `ensure_line_in_file` – safely appends a line to a file if it is not already present.
- `update_grub_cmdline` – updates GRUB parameters in an idempotent way.

### How to use the library
Add the following two lines at the top of any script:
```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root
```
After that you can replace direct `echo` statements with the appropriate logging helper, e.g.:
- `log_info "DONE"`
- `log_error "Package not found"`

All existing scripts have been updated to source the library and use these helpers where appropriate.

### Scripts Overview
- `01-install-proxmox-tools.sh` – installs required packages via `install_missing_packages`.
- `02-enable-iommu.sh` – configures IOMMU and VFIO modules using `update_grub_cmdline` and `ensure_line_in_file`.
- `03-download-cloud-image.sh` – downloads the Ubuntu cloud image if absent.
- `04-create-cloudinit-template.sh` – creates the Cloud‑Init template, with error handling via `log_error`.
- `05-create-llm-vm.sh` – provisions the LLM VM (uses shared logging).
- `06-create-monitoring-vm.sh` – provisions the monitoring VM (now sources utils).
- `07-install-docker.sh` – installs Docker if missing, using `log_error` for missing `curl`.
- `08-install-nvidia-toolkit.sh` – installs NVIDIA container toolkit, uses `log_error`.
- `09-deploy-ollama.sh` – deploys Ollama stack, logs errors with `log_error` and success with `log_info`.
- `10-deploy-monitoring.sh` – deploys the monitoring stack, logs errors similarly.
- `11-audit-network.sh` – unchanged (read‑only audit script).

### Running the workflow
Execute the top‑level helper script:
```bash
./run-all.sh
```
It will sequentially run the provisioning steps. All scripts are now idempotent and provide consistent, timestamped logs.
