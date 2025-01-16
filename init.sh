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
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo usermod -aG docker $USER
sudo docker run hello-world

# Valhalla
cd ~/data
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
cd ~/data
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