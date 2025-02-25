date
telegram-send "Started osrm build $(hostname)"
cd ~/data
rm -rf osrm_full
mkdir osrm_full
cd osrm_full
cp ~/data/AutoRouteServices/osrm/bicycle.lua
curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf

docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-extract -p /data/bicycle.lua /data/planet-latest.osm.pbf || echo "osrm-extract failed"
docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-partition /data/planet-latest.osrm || echo "osrm-partition failed"
docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend osrm-customize /data/planet-latest.osrm || echo "osrm-customize failed"
date
sudo chmod 644 planet-latest.osrm.fileIndex
telegram-send "Finished osrm build $(hostname)"