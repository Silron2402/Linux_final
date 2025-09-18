#!bin/bash

# Проверяем права суперпользователя
if [ "$(id -u)" != "0" ]; then
    echo "Необходимо запускать скрипт от имени root или с sudo"
    exit 1
fi

#обновим систему
echo "Обновление системы..."
sudo apt update -y

#Выполним установку ssh-сервера
echo "Установка OpenSSH Server..."
sudo apt install -y  openssh-server

#Включение автоматического запуска ssh сервера при старте системы
echo "Включение автозапуска SSH..."
sudo systemctl enable ssh

#старт ssh сервера
echo "Запуск SSH..."
sudo  systemctl start ssh

# Настройка файрвола
echo "Настройка UFW для SSH..."
sudo ufw allow ssh
sudo ufw enable

# Создание резервной копии конфигурации
echo "Создание резервной копии конфигурации..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

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

# Генерация ключей
#echo "Генерация SSH-ключей..."
ssh-keygen -t rsa -b 4096

# Вывод статуса
echo "Проверка статуса SSH..."
sudo systemctl status ssh

echo "Настройка завершена!"



# Указываем хост и порт
_HOST="127.0.0.1"
_PORT=22

# Проверка доступности хоста через ping
ping -q -W 5 -c 1 $_HOST >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Хост недоступен"
    exit 1
fi

# Проверка доступности порта
timeout 5 bash -c "</dev/tcp/$_HOST/$_PORT"
if [ $? -ne 0 ]; then
    echo "Порт 22 недоступен"
    exit 1
fi

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
