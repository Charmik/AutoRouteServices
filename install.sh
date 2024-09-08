#!/bin/bash
set -ex


services=("opentopodata.service" "autoroute.service")

# Iterate over the array and print each service
for service in "${services[@]}"; do
    cp $service /etc/systemd/system/"$service"
    systemctl daemon-reload
    systemctl enable "$service"
    systemctl start "$service"
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