apt install osmium-tool
mkdir ~/disk/share/osrm_for_CI
cd ~/disk/share/osrm_for_CI
rm -rf ~/disk/share/osrm_for_CI/*
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
rm merged.osm.pbf; osmium merge *pbf -o merged.osm.pbf

cp ~/disk/traffic_dumps/traffic_final.csv .

cp -r ~/disk/osrm-backend/profiles/lib/ .

~/disk/osrm-backend/build/osrm-extract -p bicycle.lua merged.osm.pbf || echo "osrm-extract failed"
~/disk/osrm-backend/build/osrm-partition merged.osrm || echo "osrm-partition failed"
~/disk/osrm-backend/build/osrm-customize merged.osrm --segment-speed-file traffic_final.csv || echo "osrm-customize failed"

sudo chmod 644 merged.osrm.fileIndex
rm *.pbf
echo 123

cd ~/data
rm -rf osrm_for_CI
cp -r ~/disk/share/osrm_for_CI ~/data