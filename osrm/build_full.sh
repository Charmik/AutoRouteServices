DATE=$(date +%d.%m.%Y)
date
telegram-send "Started osrm build $(hostname)"
cd ~/disk
#cd /home/charm/disk/share
rm -rf osrm_full_$DATE
mkdir osrm_full_$DATE
cd osrm_full_$DATE
cp /home/charm/data/AutoRouteServices/osrm/bicycle.lua .
curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf

cp ~/disk/traffic_dumps/traffic_final.csv .

cp -r ~/disk/osrm-backend/profiles/lib/ .

date
#docker run --rm -t --platform linux/amd64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /data/bicycle.lua /data/planet-latest.osm.pbf || echo "osrm-extract failed"
~/disk/osrm-backend/build/osrm-extract -p bicycle.lua planet-latest.osm.pbf || echo "osrm-extract failed"
telegram-send "Extract finished $(hostname)"

#docker run --rm -t --platform linux/amd64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition --max-cell-sizes=1024,16384,262144,4194304 /data/planet-latest.osrm || echo "osrm-partition failed"
~/disk/osrm-backend/build/osrm-partition --max-cell-sizes=1024,16384,262144,4194304 planet-latest.osrm || echo "osrm-partition failed"
telegram-send "Partition finished $(hostname)"

#docker run --rm -t --platform linux/amd64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /data/planet-latest.osrm || echo "osrm-customize failed"
~/disk/osrm-backend/build/osrm-customize planet-latest.osrm --segment-speed-file traffic_final.csv || echo "osrm-customize failed";
telegram-send "Customize finished $(hostname)"

sudo chmod 644 planet-latest.osrm.fileIndex
date
rm planet-latest.osm.pbf
telegram-send "Finished osrm build $(hostname)"
echo "Processed: ~/disk/osrm_full_$DATE"
#copy:
#to hz2
rsync -r --progress ~/disk/osrm_full_$DATE charm@88.99.161.250:/home/charm/disk/
#to hz4
rsync -r --progress ~/disk/osrm_full_$DATE charm@65.21.136.166:/home/charm/disk/
telegram-send "Finished rsync osrm to testing/prod"

~/disk/osrm-backend/build/osrm-routed --algorithm mld --mmap on planet-latest.osrm -p 8003

#CH
#docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-contract /data/planet-latest.osrm || echo "osrm-contract failed"

#run
#/usr/bin/docker run --rm --network=host -v "${PWD}:/data" --name osrm-backend ghcr.io/project-osrm/osrm-backend osrm-routed --algorithm mld --mmap on /data/planet-latest.osrm -p 8003



#docker run --rm -t --platform linux/amd64 -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /data/bicycle.lua /data/planet-latest.osm.pbf || echo "osrm-extract failed"
#telegram-send "Extract finished $(hostname)"
#docker run --rm -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-contract --algorithm ch /data/planet-latest.osrm || echo "osrm-contract failed"
#telegram-send "CH finished $(hostname)"