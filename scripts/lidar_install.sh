#!bin/bash

#команды настройки выполнения скрипта установки драйверов лидара
#прерывать скрипт при любой ошибке;
#сообщение об ошибке при обнаружении неопределенных переменных
#настройка пайпа возвращать код ошибки первой упавшей команды.
set -eu -o pipefail

# Обработка прерывания скриптом (Ctrl+C)
trap 'log_msg "Скрипт прерван пользователем"; exit 1' INT

#логирование с датой для отладки
log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# Функция проверки установленного пакета
is_package_installed() {
    local package="$1"
    dpkg -s "$package" &>/dev/null
}

#Получение имени пользователя и адреса домашнего каталога
USERNAME=$(whoami)
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
# Путь к рабочей директории
WORKSPACE_DIR="$USER_HOME/ros2_ws"

#проверка интернет-соединения
if ! ping -c 1 github.com &> /dev/null; then
    log_msg "Отсутствует интернет‑соединение!"
    exit 1
fi

#Проверка прав суперпользователя
if [ "$(id -u)" != "0" ]; then
    log_msg "Необходимо запустить скрипт от имени root или c sudo"
    exit 1
fi

# Переход в директорию src рабочего пространства ROS 2
cd "$WORKSPACE_DIR/src" || {
    log_msg "Ошибка: директория $WORKSPACE_DIR/src не найдена!"
    exit 1
}

# Установка git (если не установлен)
if ! is_package_installed git; then
    log_msg "Установка пакета git..."
    apt install -y git
else
    log_msg "Пакет git уже установлен."
fi

# Клонирование репозиториев
REPO_URL="https://github.com/Slamtec/rplidar_ros.git"
#рабочая директория
REPO_DIR="$WORKSPACE_DIR/src/slamtec"


if [ -d "$REPO_DIR" ]; then
    log_msg "Репозиторий существует. Выполняем обновление (git pull)..."
    cd "$REPO_DIR" && git pull
else
    log_msg "Клонирование репозитория $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Переход в корневую директорию workspace
cd "$WORKSPACE_DIR" || {
    log_msg "Ошибка: не удалось перейти в $WORKSPACE_DIR!"
    exit 1
}

#ros version
DFF=$(rosversion -d)

#Выполним сборку пакета с помощью команды:
source /opt/ros/$DFF/setup.bash


# Сборка workspace с помощью colcon
log_msg "Сборка workspace с colcon..."
colcon build --symlink-install

# Активация окружения
source ./install/setup.bash

# Добавление постоянной активации в .bashrc
if ! grep -q "source $WORKSPACE_DIR/install/setup.bash" ~/.bashrc; then
    log_msg "Добавление настройки в ~/.bashrc..."
    echo "source $WORKSPACE_DIR/install/setup.bash" >> ~/.bashrc
else
    log_msg "~/.bashrc уже содержит настройку окружения."
fi

# Перезагрузка .bashrc для текущего сеанса
source ~/.bashrc

log_msg "Скрипт успешно завершён!"

roslaunch rplidar_ros rplidar_c1.launch
