#!/bin/bash
set -ex


#services=("opentopodata.service" "autoroute.service")
services=("autoroute.service")

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

cd /home/charm/data/AutoRouteServices

# Iterate over the array and print each service
for service in "${services[@]}"; do
    sudo cp $service /etc/systemd/system/"$service"
    sudo systemctl daemon-reload
    sudo systemctl enable "$service"
    sudo systemctl start "$service"
    sudo systemctl restart "$service"
    sleep 10
done


#cp XXX.service /etc/systemd/system/
#
#sudo systemctl status autoroute
#sudo systemctl start autoroute
#sudo systemctl restart autoroute


#elevation service
#cd ~/data/opentopodata && make build && make run

#sudo systemctl daemon-reload  # Reload systemd to recognize the new service
#sudo systemctl enable opentopodata.service  # Enable the service to start on boot
#sudo systemctl start opentopodata.service   # Start the service immediately
#journalctl -u opentopodata.service -f


#dependency: https://stackoverflow.com/questions/21830670/start-systemd-service-after-specific-service
#[Unit]
#Description=My Website
#After=syslog.target network.target mongodb.service

#Wants=other.service