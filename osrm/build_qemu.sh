set -x

apt install osmium-tool
HOSTNAME=$(hostname)
BUILD_DIR="osrm_for_mac_${HOSTNAME}"
mkdir -p ~/disk/share/${BUILD_DIR}
cd ~/disk/share/${BUILD_DIR}
rm -rf ~/disk/share/${BUILD_DIR}/*
cp ~/data/AutoRouteServices/osrm/bicycle.lua .

curl -OL https://download.geofabrik.de/europe/cyprus-latest.osm.pbf
curl -OL https://download.geofabrik.de/russia/northwestern-fed-district-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/united-kingdom-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/germany-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/austria-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/switzerland-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/denmark-latest.osm.pbf
curl -OL https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf
curl -OL https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/czech-republic-latest.osm.pbf

ls -lh *.osm.pbf
rm merged.osm.pbf
osmium merge *pbf -o merged.osm.pbf
ls -la merged.osm.pbf

cp ~/disk/traffic_dumps/traffic_final.csv .
cp -r ~/disk/osrm-backend/profiles/lib/ .

~/disk/osrm-backend/build/osrm-extract -p bicycle.lua merged.osm.pbf || echo "osrm-extract failed"
~/disk/osrm-backend/build/osrm-partition merged.osrm || echo "osrm-partition failed"
~/disk/osrm-backend/build/osrm-customize merged.osrm --segment-speed-file traffic_final.csv || echo "osrm-customize failed"

rm *.pbf
echo 123