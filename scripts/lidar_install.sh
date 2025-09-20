#!bin/bash

# Перeйдем в папку ~/ros2_ws/src
cd ~/ros2_ws/src

echo ls

#установка git
sudo apt install git -y

# Клонирование репозитория с помощью команды:
git clone https://github.com/ros-drivers/velodyne.git

# https://github.com/Slamtec/rplidar_ros.git

# Переход в корневую директорию workspace:
cd ~/ros2_ws

#Выполним сборку пакета с помощью команды:
source /opt/ros/iron/setup.bash

colcon build --symlink-install

# Выполним активацию окружения:
source ./install/setup.bash

#Для постоянного добавления в окружение введем команду:
echo "source ~/ros2_ws/install/setup.bash" >> ~/.bashrc
source ~/.bashrc
