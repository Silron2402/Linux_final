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

#обновим систему
log_msg "Обновление системы..."
if ! apt update -y; then
    log_msg "Ошибка обновления системы"
    exit 1
fi

# Установка git (если не установлен)
if ! is_package_installed  "openssh-server"; then
    log_msg "Установка OpenSSH Server..."
    apt install -y openssh-server
else
    log_msg "OpenSSH Server уже установлен."
fi

#Включение автоматического запуска ssh сервера при старте системы
#Включение автозапуска SSH...
log_msg "Включение автозапуска SSH..."
if systemctl enable ssh --now; then
    log_msg "Автозапуск SSH включен"
else
    log_msg "Ошибка: не удалось включить автозапуск SSH"
    exit 1
fi

#старт ssh сервера
if systemctl is-active --quiet ssh; then
    log_msg "SSH-сервер уже запущен"
else
    systemctl start ssh
    if systemctl is-active --quiet ssh; then
        log_msg "SSH-сервер успешно запущен"
    else
        log_msg "Ошибка: не удалось запустить SSH-сервер"
        exit 1
    fi
fi

# Настройка файрвола
log_msg "Настройка UFW для SSH..."
if ufw allow ssh; then
    log_msg "Разрешены входящие SSH‑соединения через брандмауэр UFW (порт 22)"
else
    log_msg "Ошибка: не удалось открыть порт SSH в UFW"
    exit 1
fi

# Активация UFW (если ещё не активен)
if ! ufw status | grep -q "Status: active"; then
    log_msg "Активируем UFW..."
    if ufw enable; then
        log_msg "UFW успешно активирован"
    else
        log_msg "Ошибка: не удалось активировать UFW"
        exit 1
    fi
else
    log_msg "UFW уже активен"
fi


# Создание резервной копии конфигурации
log_msg "Создание резервной копии конфигурации..."

if cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup; then
    log_msg "Резервная копия конфигурации успешно создана"
else
    log_msg "Ошибка: не удалось создать резервную копию конфигурации"
    exit 1
fi

# Генерация ключей
log_msg  "Генерация SSH-ключей..."
# Параметры по умолчанию
KEY_TYPE="rsa"           # Тип ключа (rsa, ed25519 и др.)
KEY_BITS=4096             # Длина ключа для RSA
KEY_PATH="$HOME/.ssh/id_rsa"  # Путь к приватному ключу
COMMENT="${USER_HOME}@$(hostname)"   # Комментарий (можно переопределить)
PASSPHRASE=""            # Пустая passphrase 

#Проверка существования ключа
if [ -f "$KEY_PATH" ]; then
    log_msg "Ошибка: ключ уже существует: $KEY_PATH"
    log_msg "Чтобы перезаписать, удалите файл вручную или укажите другой путь."
    exit 1
fi

if ssh-keygen -t "$KEY_TYPE" -f "$KEY_PATH" -b $KEY_BITS; then
   log_msg "Генерация ключей успешно выполнена"
else
    log_msg "Ошибка: не удалось выполнить генерацию ключей"
    exit 1
fi

if [ $? -eq 0 ]; then
    log_msg "Генерация ключей успешно выполнена"
    log_msg "Приватный ключ: $KEY_PATH"
    log_msg "Публичный ключ: ${KEY_PATH}.pub"
    # Выводим отпечаток ключа (как в ssh-keygen)
    ssh-keygen -l -f "$KEY_PATH"
else
    log_msg "Ошибка: не удалось выполнить генерацию ключей"
    exit 1
fi

_CHECK=0
# Вывод статуса
log_msg "Проверка статуса SSH..."
# 1. Статус службы
if systemctl is-active --quiet ssh; then
    echo "✓ SSH-сервер запущен"
    ((_CHECK++))
    else
    echo "✗ SSH-сервер не запущен"
fi

# 2. Автозапуск
if systemctl is-enabled --quiet ssh; then
    echo "✓ Автозапуск включён"
    ((_CHECK++))
else
    echo "✗ Автозапуск отключён"
fi

# 3. Порт 22
if ss -tulnp | grep -q ':22\b'; then
    echo "✓ Порт 22 открыт"
    ((_CHECK++))
else
    echo "✗ Порт 22 не открыт"
fi

# 4. Конфигурация
if grep -q "^Port 22" /etc/ssh/sshd_config; then
    echo "✓ Конфигурация: порт 22"
else
    echo "✗ Конфигурация: порт не 22 или закомментирован"
fi

if $_CHECK == 4; then
    log_msg "Настройка завершена!"
    else
    echo "✗ Настройка не выполнена"
    exit 1
fi

# Указываем хост и порт
_HOST="127.0.0.1"
_PORT=22

log_msg "Проверка доступности порта $_PORT на хосте $_HOST..."

# 1. Проверка порта через /dev/tcp
if timeout 5 bash -c "</dev/tcp/$_HOST/$_PORT"; then
    log_msg "✓ Порт $_PORT доступен"
else
    log_msg "✗ Порт $_PORT недоступен"
    exit 1
fi

# Проверка доступности хоста через ping
ping -q -W 5 -c 1 $_HOST >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Хост недоступен"
    exit 1
fi

log_msg "Попытка SSH‑подключения к $_HOST..."

# 2. Проверка SSH‑подключения
ssh -q \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -i "$KEY_PATH" \
    "$_HOST" 'exit 0'

_RCODE=$?

if [ $_RCODE -eq 0 ]; then
    log_msg "✓ SSH‑подключение успешно"
else
    log_msg "✗ Не удалось подключиться по SSH (код ошибки: $_RCODE)"
    # Дополнительные подсказки при ошибках
    case $_RCODE in
        1)  log_msg "   Ошибка аутентификации" ;;
        2)  log_msg "   Проблемы с сетевым подключением" ;;
        255) log_msg "   SSH‑клиент вернул ошибку (возможно, тайм‑аут)" ;;
        *)  log_msg "   Неизвестная ошибка SSH" ;;
    esac
    exit 1
fi

log_msg "Все проверки завершены успешно."
exit 0





# Настройка безопасности
#echo "Настройка параметров безопасности..."
#sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
#sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
#sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config

# Изменение порта (опционально)
#read -p "Хотите изменить порт SSH? (y/n): " change_port
#if [[ $change_port == "y" ]]; then
#    read -p "Введите новый порт: " new_port
#    sudo sed -i "s/#Port 22/Port $new_port/g" /etc/ssh/sshd_config
#fi

# Перезапуск сервиса
#echo "Перезапуск SSH-сервера..."
#sudo systemctl restart ssh









# Проверка SSH-подключения
ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -i /path/to/your/key $_HOST 'exit 0'
_RCODE=$?

if [ $_RCODE -ne 0 ]; then
    echo "Не удалось подключиться по SSH"
    exit 1
else
    echo "SSH-подключение успешно"
    exit 0
fi
