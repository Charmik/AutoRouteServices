#!/bin/bash
set -ex


services=("opentopodata.service" "autoroute.service" "valhalla.service" "photon.service")

#copy opentopodata project & aster30m
cd /home/charm/data
if [ ! -d "opentopodata" ]; then
  git clone https://github.com/Charmik/opentopodata
  cd opentopodata
else
  cd opentopodata
  git pull
fi
if [ ! -d "data/aster30m" ]; then
  echo "aster30m doesn't exist so copy it from data dir"
  mv aster30m data
else
  echo "aster30m" exists
fi

cd /home/charm/data
if [ ! -d "photon" ]; then
  echo "photon doesnt exist, clone the project"
  git clone https://github.com/komoot/photon
  cd photon
  sudo apt-get install bzip2 pbzip2
  wget -O - https://download1.graphhopper.com/public/photon-db-latest.tar.bz2 | pbzip2 -cd | tar x
  ./gradlew app:es_embedded:build
else
  cd photon
  git pull
fi

cd /home/charm/data
mkdir -p AutoRoute

cd /home/charm/data/AutoRouteServices

# Iterate over the array and print each service
for service in "${services[@]}"; do
    sudo cp $service /etc/systemd/system/"$service"
    sudo systemctl daemon-reload
    sudo systemctl enable "$service"
    sudo systemctl restart "$service"

    if systemctl is-active --quiet "$service"; then
        echo "$service is running."
    else
        echo "$service is not running. exit"
        exit 42
    fi
done