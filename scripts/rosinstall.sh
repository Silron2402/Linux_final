#!/usr/bin/env bash

#команды настройки выполнения скрипта
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

#Установка версии ROS и параметров системной локали
ROS_DISTRO="humble"
ROS_VERSION="desktop-full"
#установка и экспорт переменной окружения LANG c базовыми настройками 
#для текущей сессии терминала и запускаемых в ней программ
#Нужно убедиться, что наша система использует UTF-8.
LOCALE="en_US.UTF-8"

#списки устанавливаемых пакетов
required_packages1=(
    "curl"           # Загрузка файлов
    "gnupg2"          # Работа с GPG‑ключами
    "lsb-release"    # Определение версии дистрибутива
    "software-properties-common" #установка пакета необходимого для работы с внешними репозиториями

)

required_packages2=(
    "python3-rosdep"                    # Управление зависимостями ROS
    "python3-wstool"                    # Управление рабочими пространствами
    "python3-colcon-common-extensions"  # Утилиты для сборки пакетов через colcon
    "build-essential"               # Компиляторы и инструменты сборки (gcc, g++, make)
    "python3-flake8"
    "python3-pytest-cov"
    "python3-pip"                       # Менеджер пакетов Python
)

#Настройки создания workspace 
# По умолчанию — не создавать workspace
CREATE_WORKSPACE=false

# анализ аргументов
for arg in "$@"; do
    case $arg in
        -w|--workspace)
            CREATE_WORKSPACE=true
            ;;
        -h|--help)
            echo "Использование: $0 [опции]"
            echo "  -w, --workspace  Создать и настроить ROS 2 workspace"
            echo "  -h, --help       Показать эту справку"
            exit 0
            ;;
        *)
            echo "Неизвестная опция: $arg"
            echo "Используйте -h для справки."
            exit 1
            ;;
    esac
done

#Получение имени пользователя и адреса домашнего каталога
USERNAME=$(whoami)
#USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)  $SUDO_USER
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)  $SUDO_USER
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

#Проверка версии операционной системы
. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "22.04" ]]; then
    log_msg "Ошибка: поддерживается только Ubuntu 22.04 LTS"
    exit 1
fi

# Установка и настройка локали
log_msg "Настройка системной локали..."
apt-get update
apt-get install -y locales
locale-gen "$LOCALE"
update-locale LC_ALL="$LOCALE" LANG="$LOCALE"
export LANG="$LOCALE" LC_ALL="$LOCALE"

#Выполним установку и настройку базовых пакетов
log_msg "Установка базовых пакетов..."
for pkg in "${required_packages1[@]}"; do
    if ! is_package_installed "$pkg"; then
        log_msg "Пакет $pkg не установлен. Устанавливаем..."
        apt-get install -y "$pkg"
    else
        log_msg "Пакет $pkg уже установлен"
    fi
done

# Добавление репозитория ROS2
log_msg "Добавление репозитория ROS2..."
add-apt-repository universe -y

#Добавление  GPG-ключа ROS
if ! curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | tee /usr/share/keyrings/ros-archive-keyring.gpg > /dev/null; then
    log_msg "Ошибка: не удалось добавить GPG‑ключ ROS"
    exit 1
fi


#Добавление репозитория в список источников

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null
if [ $? -ne 0 ]; then
    log_msg "Ошибка: не удалось записать в sources.list.d"
    exit 1
fi

# Обновление списка пакетов
log_msg "Обновление списка пакетов"
apt-get update

#Установка ROS2
if is_package_installed "ros-$ROS_DISTRO-$ROS_VERSION"; then
    log_msg "Пакет ROS2 уже установлен"
else
    echo "Установка ROS2 full версии..."
    #установка
    apt-get install -y "ros-$ROS_DISTRO-$ROS_VERSION"
    # Проверка установки
    if [ ! -d "/opt/ros/$ROS_DISTRO" ]; then
        log_msg "Ошибка: ROS 2 не установлен!"
        exit 1
    fi
fi

# Определяем домашний каталог пользователя, запустившего скрипт (даже через sudo)
if [ -n "$SUDO_USER" ]; then
    # Если скрипт запущен через sudo, берём домашний каталог исходного пользователя
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
elif [ -n "$SUDO_UID" ]; then
    # Альтернатива: по UID
    USER_HOME=$(getent passwd "$SUDO_UID" | cut -d: -f6)
else
    # Иначе используем текущий $HOME (например, если запущен без sudo)
    USER_HOME="$HOME"
fi

# Проверяем, что USER_HOME определён
if [ -z "$USER_HOME" ]; then
    log_msg "Ошибка: не удалось определить домашнего каталога пользователя"
    exit 1
fi

BASHRC="$USER_HOME/.bashrc"

echo $BASHRC

#Настройка окружения
log_msg "Настройка окружения ROS2..."

# Определяем путь к setup.bash
ROS_SETUP="/opt/ros/$ROS_DISTRO/setup.bash"

# Проверяем существование файла
if [ ! -f "$ROS_SETUP" ]; then
    log_msg "Ошибка: файл $ROS_SETUP не найден!"
    exit 1
fi

# Проверяем существование файла
if [ ! -f $BASHRC ]; then
    log_msg "Ошибка: файл $BASHRC не найден!"
    exit 1
fi

# Проверяем, не добавлена ли строка раньше
if ! grep -q "source $ROS_SETUP" "$BASHRC"; then
    echo "source $ROS_SETUP" >> "$BASHRC"
    log_msg "Строка 'source $ROS_SETUP' добавлена в $BASHRC"
else
    log_msg "Строка 'source $ROS_SETUP' уже есть в $BASHRC"
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

##Установка и настройка дополнительных инструментов
log_msg "Установка дополнительных инструментов..."
for pkg in "${required_packages2[@]}"; do
    if ! is_package_installed "$pkg"; then
        log_msg "Пакет $pkg не установлен. Устанавливаем..."
        apt-get install -y "$pkg"
    else
        log_msg "Пакет $pkg уже установлен"
    fi
done

#инициализация rosdep
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    log_msg "Инициализация rosdep..."
    rosdep init || { log_msg "rosdep init failed"; exit 1; }
else
    log_msg "rosdep уже инициализирован"
fi
rosdep update

log_msg "Инициализация rosdep... done"  

#применение изменений из файла .bashrc в текущей сессии терминала без его перезапуска
set +u #Отключим проверку обнаружения неопределенных переменных
source $ROS_SETUP
set -u #Включим проверку обнаружения неопределенных переменных

#Финальное сообщение
RESULT=$(which ros2 2>&1)
if [ $? -eq 0 ]; then
    log_msg "Установка ROS2 завершена успешно!"
else    
    log_msg "Установка ROS2 не завершена!"
    exit 1
fi

#настройка workspace

if [ "$CREATE_WORKSPACE" = true ]; then
    log_msg "Начинаем настройку ROS 2 workspace..."

    #Проверка существования workspace
    if [ -d "$WORKSPACE_DIR" ]; then
        log_msg "Workspace уже существует: $WORKSPACE_DIR"
        log_msg "Проверка настройки окружения..."
    else
        log_msg "Создаём workspace: $WORKSPACE_DIR"
        mkdir -p "$WORKSPACE_DIR/src" || {
            log_msg "Ошибка: не удалось создать директорию $WORKSPACE_DIR"
            exit 1
        }
    fi

    #Инициализация workspace
    log_msg "Выполняем первую сборку workspace..."
    cd "$WORKSPACE_DIR" || {
        log_msg "Ошибка: не удалось перейти в $WORKSPACE_DIR"
        exit 1
    }
    
    colcon build --symlink-install || {
        log_msg "Ошибка при сборке workspace. Проверьте зависимости."
        exit 1
    }

    #Настройка автоактивации в .bashrc
    SETUP_FILE="$WORKSPACE_DIR/install/setup.bash"

    if [ -f "$SETUP_FILE" ]; then
        if ! grep -q "source $SETUP_FILE" "$BASHRC"; then
            echo "source $SETUP_FILE" >> "$BASHRC"
            log_msg "Добавлена автоактивация workspace в $BASHRC"
        else
            log_msg "Автоактивация workspace уже настроена в $BASHRC"
        fi
    else
        log_msg "Файл $SETUP_FILE не найден. Сборка, возможно, не завершена."
        exit 1
    fi

    #Активируем среду в текущем сеансе
    set +u #Отключим проверку обнаружения неопределенных переменных
    source "$SETUP_FILE"
    set -u #Включим проверку обнаружения неопределенных переменных
    log_msg "Среда ROS 2 активирована в текущем терминале"

    log_msg "Workspace готов: $WORKSPACE_DIR"
    log_msg "Для отмены автоактивации удалите строку 'source $SETUP_FILE' из $BASHRC"
else
    log_msg "Настройка workspace пропущена (используйте -w или --workspace, чтобы включить)"
fi


