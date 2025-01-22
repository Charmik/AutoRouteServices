#!/bin/bash

# Enable error handling and command trace
set -ex

# Update and install necessary packages without interaction
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get -y install openssh-client openssh-server
sudo apt-get -y install vim tmux maven tmux git postgresql xfsprogs lsof rsyslog snapd python3-pip pipx jq aha gdal-bin libgdal-dev tree

# Setup PostgreSQL database without interaction
sudo -i -u postgres psql << EOF
CREATE DATABASE charmdb;
CREATE ROLE charm WITH LOGIN SUPERUSER PASSWORD 'qwe';
GRANT ALL PRIVILEGES ON DATABASE charmdb TO charm;
EOF

# docker
sudo apt-get -y install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

DISTRO=$(grep "^ID=" /etc/os-release | cut -d '=' -f 2)

if [[ "$DISTRO" == "ubuntu" ]]; then
  echo "Using Ubuntu Docker repository"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -c | awk '{print $2}') stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
elif [[ "$DISTRO" == "debian" ]]; then
  echo "Using Debian Docker repository"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(lsb_release -c | awk '{print $2}') stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
else
  echo "Unsupported distribution: $DISTRO"
  exit 1
fi

sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -f /usr/local/bin/docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo systemctl start docker
sudo usermod -aG docker $USER
sudo docker run hello-world

# Valhalla
cd ~/disk
if [ ! -d "docker-valhalla" ]; then
  git clone https://github.com/gis-ops/docker-valhalla
fi
  cd docker-valhalla
  git pull
  cp ~/data/AutoRouteServices/valhalla/docker-compose.yml .
  cp ~/data/AutoRouteServices/valhalla/docker-compose-build.yml .
  ulimit -n 65536
# docker compose -f docker-compose.yml up --build
# docker compose -f docker-compose-build.yml up --build

# OpenTopoData
cd ~/disk
if [ ! -d "opentopodata" ]; then
  git clone https://github.com/Charmik/opentopodata
fi
cd opentopodata
git pull
sudo make build
cd data
mkdir -p aster30m
cd aster30m
wget -r -np -nH --cut-dirs=3 -R "index.html*" -N -P . http://autoroute.shop/opentopodata/data/aster30m/
# make run


# add AutoRoute: app.config && config/cool_tags.txt