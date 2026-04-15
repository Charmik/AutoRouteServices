#https://prometheus.io/docs/prometheus/latest/getting_started/

cd ~/disk
https://github.com/prometheus/prometheus/releases/download/v3.8.0-rc.1/prometheus-3.8.0-rc.1.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
cd prometheus-*

cp ~/data/AutoRouteServices/prometheus/prometheus.yml .

sudo cp ~/data/AutoRouteServices/prometheus.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl status prometheus