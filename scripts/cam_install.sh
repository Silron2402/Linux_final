#!bin/bash

# Перeйдем в папку ~/ros2_ws/src
cd ~/ros2_ws/src

#установка git
sudo apt install git -y

# Клонирование репозитория с помощью команды:
git clone https://github.com/ros-drivers/usb_cam.git

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
