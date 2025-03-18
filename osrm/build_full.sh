date
telegram-send "Started osrm build $(hostname)"
cd ~/disk
rm -rf osrm_full
mkdir osrm_full
cd osrm_full
cp ~/data/AutoRouteServices/osrm/bicycle.lua .
curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf

docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-extract -p /data/bicycle.lua /data/planet-latest.osm.pbf || echo "osrm-extract failed"
docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-partition /data/planet-latest.osrm || echo "osrm-partition failed"
docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-customize /data/planet-latest.osrm || echo "osrm-customize failed"
date
telegram-send "Finished osrm build $(hostname)"
rm planet-latest.osm.pbf
sudo chmod 644 planet-latest.osrm.fileIndex