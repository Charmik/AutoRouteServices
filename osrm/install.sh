#!/bin/bash
set -x

mkdir -p ~/data
mkdir -p ~/disk
mkdir -p ~/.m2/repository/com/wolt

# osrm-backend gets boost/tbb/lua/bzip2/libxml2/libarchive from vcpkg now (see
# vcpkg.json), so the -dev packages for those are gone. What's left is the
# toolchain plus the autotools bits some vcpkg ports need to bootstrap.
sudo apt-get install -y htop vim tmux pipx maven osmium-tool \
    git build-essential cmake ninja-build pkg-config \
    autoconf automake libtool curl zip unzip tar
wget https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb
sudo dpkg -i jdk-25_linux-x64_bin.deb

sudo apt remove cmake
sudo apt install -y gpg wget
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/kitware.list
sudo apt update
sudo apt install -y cmake

sudo apt install software-properties-common
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
# gcc-11 is too old: osrm-backend needs C++20 with working <format>/chrono
# formatters. CI builds on gcc-14 and gcc-15.
sudo apt install -y gcc-14 g++-14

# vcpkg provides osrm-backend's dependencies in manifest mode. build_osrm_native.sh
# clones it on demand, but export VCPKG_ROOT so cmake --preset works by hand too.
echo 'export VCPKG_ROOT=$HOME/vcpkg' >> ~/.bashrc

sudo apt install -y python3-pip
pip3 install --break-system-packages aiohttp



pipx install --force telegram-send
echo 'export PATH="$PATH:/home/$USER/.local/bin"' >> ~/.bashrc
/home/$USER/.local/bin/telegram-send --configure
1093278356:AAE4RLde57ak9eQicn_nQuO1_nz0szxGgtc
source ~/.bashrc


#mount disk
