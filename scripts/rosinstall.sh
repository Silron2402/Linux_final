#!bin/bash

#Проверим права суперпользователя
if [ "$(id -u)" != "0" ]; then
    echo "Необходимо запустить скрипт от имени root или c sudo"
    exit 1
fi

#Выполним установку и настройку системной локали
echo "Настройка системной локали..."
sudo apt-get update && sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
echo "Завершена установка и настройка системной локали"

#Настройка репозиториев
#echo "Выполняется настройка репозиториев"
#sudo apt install -y software-properties-common
#sudo add-apt-repository universe

#Добавление репозитория ROS2
echo "Добавление репозитория ROS2..."
sudo apt update && sudo apt install -y curl gnupg lsb-release
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(source /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

#Установка ROS2
echo "Установка ROS2 Desktop версии..."
sudo apt update
sudo apt install -y ros-iron-desktop

#Настройка окружения
echo "Настройка окружения ROS2..."
echo "source /opt/ros/iron/setup.bash" >> ~/.bashrc
source ~/.bashrc


echo "Установка дополнительных инструментов..."
sudo apt install -y \
    python3-rosdep \
    python3-vcstool \
    python3-colcon-common-extensions \
    python3-flake8 \
    python3-pytest-cov \
    python3-pip


echo "Инициализация rosdep.."
sudo rosdep init
rosdep update

#Обновление существующего терминала
source ~/.bashrc
echo "Установка ROS2 завершена успешно!"

