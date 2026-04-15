#!/bin/bash
set -x

mkdir -p ~/data
mkdir -p ~/disk
mkdir -p ~/.m2/repository/com/wolt

sudo apt-get install -y python3.8-venv htop vim tmux pipx git build-essential git cmake pkg-config libbz2-dev libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libtbb-dev maven
wget https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb
sudo dpkg -i jdk-25_linux-x64_bin.deb

sudo apt remove cmake
sudo apt install -y gpg wget
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/kitware.list
sudo apt update
sudo apt install cmake

sudo apt install software-properties-common
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install gcc-11 g++-11

sudo apt install python3-pip
pip3 install --break-system-packages aiohttp



pipx install --force telegram-send
echo 'export PATH="$PATH:/home/$USER/.local/bin"' >> ~/.bashrc
/home/$USER/.local/bin/telegram-send --configure
1093278356:AAE4RLde57ak9eQicn_nQuO1_nz0szxGgtc
source ~/.bashrc


#mount disk
