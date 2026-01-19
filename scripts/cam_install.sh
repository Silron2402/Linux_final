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
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# Путь к установочной директории
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
    mkdir -p "$WORKSPACE_DIR/src"
    if ! cd "$WORKSPACE_DIR/src"; then
        log_msg "Ошибка: директория $WORKSPACE_DIR/src не была создана!"
        exit 1
    fi
}

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

# Параметры репозитория
#git clone https://github.com/Slamtec/rplidar_ros.git -b ros2
REPO_URL="https://github.com/ros-drivers/usb_cam.git"  
#рабочая директория
REPO_DIR="$WORKSPACE_DIR/src/usbcam_ros"

#проверка существования репозитория
if [ -d "$REPO_DIR" ]; then
    log_msg "Репозиторий существует. Выполняем обновление (git pull)..."
    cd "$REPO_DIR" && git pull
else
    log_msg "Клонирование репозитория $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR" -b ros2
fi

# Переход в корневую директорию workspace
cd "$WORKSPACE_DIR" || {
    log_msg "Ошибка: не удалось перейти в $WORKSPACE_DIR!"
    exit 1
}

# Определение ROS_DISTRO по наличию директорий
ROS_DISTROS=$(ls /opt/ros 2>/dev/null | tail -1)
if [ -n "$ROS_DISTROS" ]; then
    ROS_DISTRO="$ROS_DISTROS"
    log_msg "Автоматически определён ROS_DISTRO=$ROS_DISTRO"
else
    log_msg "Ошибка: не удалось определить ROS_DISTRO. Убедитесь, что ROS установлен и sourced."
    exit 1
fi

#Выполним сборку пакета 
# Определяем путь к setup.bash
ROS_SETUP="/opt/ros/$ROS_DISTRO/setup.bash"

# Проверяем существование файла
if [ ! -f "$ROS_SETUP" ]; then
    log_msg "Ошибка: файл $ROS_SETUP не найден!"
    exit 1
fi

# Применяем настройки в текущем окружении
set +u #Отключим проверку обнаружения неопределенных переменных
if source $ROS_SETUP; then
    log_msg "Окружение ROS2 настроено успешно!"
else
    log_msg "Ошибка: не удалось выполнить source $ROS_SETUP"
    exit 1
fi
set -u #Включим проверку обнаружения неопределенных переменных


# Сборка workspace с помощью colcon
log_msg "Сборка workspace с colcon..."
log_msg "Мы находимся в директории $PWD"
colcon build --symlink-install || {
    log_msg "Ошибка сборки colcon!"
    exit 1
}

# Активация окружения
set +u #Отключим проверку обнаружения неопределенных переменных
if source ./install/setup.bash; then
    log_msg "Окружение активировано успешно!"
else
    log_msg "Ошибка: не удалось выполнить активацию окружения"
    exit 1
fi
set -u #Включим проверку обнаружения неопределенных переменных

# Добавление постоянной активации в .bashrc
if ! grep -q "source $WORKSPACE_DIR/install/setup.bash" ~/.bashrc; then
    log_msg "Добавление настройки в ~/.bashrc..."
    echo "source $WORKSPACE_DIR/install/setup.bash" >> ~/.bashrc
else
    log_msg "~/.bashrc уже содержит настройку окружения."
fi

# Перезагрузка .bashrc для текущего сеанса
#применение изменений из файла .bashrc в текущей сессии терминала без его перезапуска
set +u #Отключим проверку обнаружения неопределенных переменных
source ~/.bashrc
set -u #Включим проверку обнаружения неопределенных переменных

if ! ros2 pkg list | grep -q "usb_cam"; then
    log_msg "ОШИБКА: Пакет usb_cam не найден в ROS2!"
    exit 1
else
    log_msg "✓ Пакет usb_cam обнаружен в ROS2."
fi

# 2. Проверка наличия скомпилированных пакетов ROS
if ! colcon list --base-paths "$WORKSPACE_DIR/src" --packages-select usb_cam &>/dev/null; then
    log_msg "ОШИБКА: Пакет usb_cam не обнаружен в workspace!"
    exit 1
else
    log_msg "✓ Пакет usb_cam_ros успешно установлён!"
fi





# Переход в корневую директорию workspace:
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -y

#Выполним сборку пакета с помощью команды:
cd ~/ros2_ws
colcon build

# Выполним активацию окружения:
source ./install/setup.bash

#Для постоянного добавления в окружение введем команду:
echo "source ~/ros2_ws/install/setup.bash" >> ~/.bashrc
source ~/.bashrc
