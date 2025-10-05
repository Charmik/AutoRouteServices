set -x

apt install osmium-tool

BUILD_DIR="osrm_merged"
rm -rf ~/data/osrm_for_CI
cp -r ~/disk/share/${BUILD_DIR} ~/data/osrm_for_CI

cd ~/data/osrm_for_CI

sudo systemctl restart osrm.service
sudo systemctl restart autoroute.service
~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005