set -x

apt install osmium-tool

BUILD_DIR="osrm_merged"
rm -rf ~/data/osrm_merged
cp -r ~/disk/share/${BUILD_DIR} ~/data/osrm_merged

cd ~/data/osrm_merged

sudo systemctl restart osrm.service
sudo systemctl restart autoroute.service
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005
~/disk/osrm-backend/build/osrm-routed --algorithm mld --mmap on merged.osrm -p 8005