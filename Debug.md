**Настройка отладки Bash‑скриптов на Proxmox (IP 77.50.132.85)**  

---

### 1. Базовые требования
1. **SSH‑доступ** к хосту Proxmox (root или пользователь с правами `sudo`).  
   ```bash
   ssh root@77.50.132.85
   ```
2. **Установленные утилиты** `bash`, `coreutils`, `rsyslog`/`syslog-ng` (по‑умолчанию присутствуют в Proxmox).  

---

### 2. Универсальная отладочная оболочка

В файле `scripts/lib/utils.sh` (уже подключается в каждом скрипте) добавьте вспомогательные функции, которые можно включать/выключать переменной `DEBUG`:

```bash
# utils.sh – добавить в конец файла
debug_init() {
  # Включить подробный вывод только при DEBUG=1 (или любой непустой)
  if [[ -n "${DEBUG:-}" ]]; then
    set -x               # трассировка команд
    exec > >(tee -a "/var/log/proxmox-script-$(basename "${BASH_SOURCE[0]}").log") 2>&1
    log_info "DEBUG mode enabled, output redirected to /var/log/...log"
  fi
}

# Обработчик ошибок, вызываемый при любой неявной неудаче
error_trap() {
  local exit_code=$?
  local line_no=$BASH_LINENO
  log_error "Script aborted with exit code $exit_code at line $line_no"
  # При желании отправить уведомление (mail, Telegram и т.п.)
}
trap error_trap ERR
```

В начале каждого скрипта (после `source utils.sh`) просто вызывайте:

```bash
debug_init
```

**Как включить/выключить:**  
```bash
export DEBUG=1   # включить отладку
./05-create-llm-vm.sh   # запуск с трассировкой
unset DEBUG      # отключить
```

---

### 3. Локальная отладка отдельных скриптов

*Одноразовый запуск с трассировкой* без изменения кода:

```bash
bash -x ./05-create-llm-vm.sh
```

*Запуск с фиксированным набором опций* (рекомендовано в production‑окружении):

```bash
set -euo pipefail          # уже присутствует в utils.sh
set -x                     # включить трассировку
./05-create-llm-vm.sh
```

---

### 4. Централизованное логирование

#### 4.1 Запись в системный журнал
В начале скрипта можно добавить:

```bash
exec > >(logger -t "proxmox-script-$(basename "$0")") 2>&1
```

Это отправит весь вывод (`stdout` и `stderr`) в `syslog`. Просмотр:

```bash
journalctl -t "proxmox-script-05-create-llm-vm.sh" -f
```

#### 4.2 Отправка логов на внешний сервер
Если нужен удалённый журнал (например, ваш центральный SIEM), настройте `rsyslog` на хосте Proxmox:

* `/etc/rsyslog.conf` – добавить строку:
```
*.*   @<REMOTE_LOG_SERVER_IP>:514
```
* Перезапустить:
```bash
systemctl restart rsyslog
```

Все сообщения, отправленные через `logger`, будут переданы удалённому серверу.

---

### 5. Использование встроенных журналов Proxmox

*Задачи PVE*: каждый вызов `qm` / `pct` записывается в `/var/log/pve/tasks/`.  
Просмотр последних задач:

```bash
journalctl -u pveproxy -f
# или
cat /var/log/pve/tasks/*.log | grep "<имя_скрипта>"
```

Для более детального анализа конкретного ID задачи:

```bash
cat /var/log/pve/tasks/<task-id>.log
```

---

### 6. Пример полного скрипта с отладкой

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
ensure_root

# Включаем отладку, если выставлена переменная DEBUG
debug_init

# ... остальной код скрипта ...

# Пример безопасного вызова qm set с проверкой (уже реализовано)
if ! qm set "$VMID" \
    --memory "$MEM" \
    --cores "$CORES" \
    --cpu host \
    --balloon 0 \
    --numa 1 \
    --agent enabled=1 \
    --net0 virtio,bridge=vmbr1,queues=8 \
    --ciuser ubuntu \
    --ipconfig0 "$IPCONFIG" \
    --nameserver "$STATIC_DNS" \
    --scsi0 "${STORAGE}:32" \
    --scsi1 "${STORAGE}:${DATA_DISK_SIZE},discard=on,ssd=1,iothread=1"; then
    log_error "Failed to configure VM $VMID hardware and network"
    exit 1
fi
```

---

### 7. Быстрый чек‑лист для отладки

| Шаг | Действие |
|-----|----------|
| 1 | Подключитесь по SSH к `77.50.132.85`. |
| 2 | Установите `export DEBUG=1` (или `DEBUG=1 ./script.sh`). |
| 3 | Запустите скрипт с `bash -x` или через `debug_init`. |
| 4 | Проверяйте вывод в `/var/log/proxmox-script-*.log` **или** `journalctl -t "proxmox-script-<script>.sh"`. |
| 5 | При ошибках сразу смотрите `cat /var/log/pve/tasks/*.log` для `qm`‑операций. |
| 6 | При необходимости настроьте удалённый `rsyslog` для отправки логов в централизованную систему. |

---

### 8. Что делать, если ошибка остаётся скрытой

1. **Включите `set -o pipefail`** (уже в `utils.sh`).  
2. **Добавьте `trap 'log_error "Line $LINENO failed"' ERR`** для более точного указания места падения.  
3. **Разбейте сложные команды** (например, длинный `qm set`) на несколько строк и проверяйте каждый отдельный параметр.  
4. **Сохраняйте вывод `qm` в переменную** и проверяйте её статус:  
   ```bash
   out=$(qm set ... 2>&1) || { log_error "qm set failed: $out"; exit 1; }
   ```

---

**Итого:** включите переменную `DEBUG` (или используйте `bash -x`) для трассировки, перенаправляйте вывод в журнал через `logger`/`tee`, используйте `trap ERR` для ловли ошибок, и проверяйте системные логи Proxmox. Это даст полную видимость происходящего и упростит поиск причин сбоев.