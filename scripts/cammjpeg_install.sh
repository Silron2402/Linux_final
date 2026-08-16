#!/usr/bin/env bash
set -eu -o pipefail

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

is_package_installed() {
    dpkg -s "$1" &>/dev/null
}

trap 'log_msg "Скрипт прерван пользователем"; exit 1' INT

# Определяем пользователя: если через sudo — берём SUDO_USER, иначе текущего
if [ -n "${SUDO_USER:-}" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$(whoami)"
fi

USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
WORKSPACE_DIR="$USER_HOME/ros2_ws"

if ! ping -c 1 github.com &>/dev/null; then
    log_msg "Отсутствует интернет‑соединение!"
    exit 1
fi

# Не требуем root для всего скрипта: sudo нужен только для apt
if ! is_package_installed git; then
    log_msg "Установка пакета git..."
    sudo apt update
    sudo apt install -y git
else
    log_msg "Пакет git уже установлен."
fi

mkdir -p "$WORKSPACE_DIR/src"

REPO_URL="https://github.com/artificiell/rpi_cam_ros2.git"
REPO_DIR="$WORKSPACE_DIR/src/mjpegcam_ros"

if [ -d "$REPO_DIR" ]; then
    log_msg "Репозиторий существует. Выполняем git pull..."
    cd "$REPO_DIR" && git pull
else
    log_msg "Клонирование репозитория $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

ROS_DISTROS=$(ls /opt/ros 2>/dev/null | tail -1)
if [ -z "$ROS_DISTROS" ]; then
    log_msg "Ошибка: не удалось определить ROS_DISTRO. Убедитесь, что ROS установлен."
    exit 1
fi
ROS_DISTRO="$ROS_DISTROS"
log_msg "Автоматически определён ROS_DISTRO=$ROS_DISTRO"

ROS_SETUP="/opt/ros/$ROS_DISTRO/setup.bash"
if [ ! -f "$ROS_SETUP" ]; then
    log_msg "Ошибка: файл $ROS_SETUP не найден!"
    exit 1
fi

source "$ROS_SETUP"
log_msg "Окружение ROS2 настроено успешно!"

cd "$WORKSPACE_DIR"

log_msg "Установка зависимостей через rosdep..."
rosdep update
rosdep install --from-paths src --ignore-src -y

log_msg "Сборка workspace с colcon..."
colcon build --symlink-install

source ./install/setup.bash
log_msg "Окружение активировано успешно!"

BASHRC_FILE="$USER_HOME/.bashrc"
LINE_TO_ADD="source $WORKSPACE_DIR/install/setup.bash"

if ! grep -qxF "$LINE_TO_ADD" "$BASHRC_FILE"; then
    log_msg "Добавление настройки в $BASHRC_FILE..."
    echo "$LINE_TO_ADD" >> "$BASHRC_FILE"
else
    log_msg "~/.bashrc уже содержит настройку окружения."
fi

if ros2 pkg executables | grep -q "^mjpeg_cam"; then
    log_msg "✓ Пакет mjpeg_cam обнаружен в ROS2."
else
    log_msg "ОШИБКА: Пакет mjpeg_cam не найден в ROS2! Проверьте package.xml и вывод сборки."
    exit 1
fi

log_msg "Готово: пакет установлен и окружение настроено."
