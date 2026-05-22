#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Описание: Устанавливает Docker на хост и настраивает службу.
# Использование: sudo scripts/07-install-docker.sh
# Примечание: По завершении текущий пользователь добавляется в группу docker.

# Загружаем и выполняем официальный установщик Docker.
curl -fsSL https://get.docker.com | sh

# Включаем и запускаем сервис Docker.
systemctl enable docker
systemctl start docker

# Добавляем пользователя в группу docker для использования без sudo.
if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "${SUDO_USER}"
else
    usermod -aG docker "$USER"
fi

# Проверяем установленную версию Docker.
docker version
