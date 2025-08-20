set -x

apt install osmium-tool
mkdir ~/disk/share/osrm_for_mac
cd ~/disk/share/osrm_for_mac
rm -rf ~/disk/share/osrm_for_mac/*
cp ~/data/AutoRouteServices/osrm/bicycle.lua .

curl -OL https://download.geofabrik.de/europe/cyprus-latest.osm.pbf
curl -OL https://download.geofabrik.de/russia/northwestern-fed-district-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/united-kingdom-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/germany-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/austria-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/switzerland-latest.osm.pbf
curl -OL https://download.geofabrik.de/europe/denmark-latest.osm.pbf

ls -lh *.osm.pbf
rm merged.osm.pbf; osmium merge *pbf -o merged.osm.pbf
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker run --rm -t --platform linux/arm64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /data/bicycle.lua /data/merged.osm.pbf || echo "osrm-extract failed"
docker run --rm -t --platform linux/arm64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition /data/merged.osrm || echo "osrm-partition failed"
docker run --rm -t --platform linux/arm64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /data/merged.osrm || echo "osrm-customize failed"
sudo chmod 644 merged.osrm.fileIndex
rm *.pbf
echo 123