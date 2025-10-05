#!/bin/bash
#sudo apt-get install -y htop vim tmux

mkdir ~/disk

START_TIME=$(date +%s)
DATE=$(date +%d.%m.%Y)
date
telegram-send "Started osrm build $(hostname)"
cd ~/disk

#sudo swapoff -a
#rm -f swap
#sudo fallocate -l 500G swap
#sudo chmod 600 swap
#sudo mkswap swap
#sudo swapon swap

#sudo apt install -y build-essential git cmake pkg-config libbz2-dev libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libtbb-dev

cd ~/disk
rm -rf osrm_full_$DATE
mkdir osrm_full_$DATE
cd osrm_full_$DATE

rsync -r --progress charm@88.99.161.250:/home/charm/data/AutoRouteServices/osrm/bicycle.lua .
rsync -r --progress charm@88.99.161.250:/home/charm/disk/traffic_dumps/traffic_final.csv .

#rsync -r --progress charm@88.99.161.250:/home/charm/data/AutoRouteServices/osrm/bicycle.lua charm@88.99.161.250:/home/charm/disk/traffic_dumps/traffic_final.csv .
#rsync -r --progress charm@88.99.161.250:'/home/charm/{data/AutoRouteServices/osrm/bicycle.lua,disk/traffic_dumps/traffic_final.csv}' .

cd ~/disk
if [ ! -d "osrm-backend/build" ]; then
    rm -rf osrm-backend
    git clone https://github.com/Charmik/osrm-backend.git
    cd ~/disk/osrm-backend
    git checkout fix-segfaults-asserts-hacks
    mkdir -p build
    cd ~/disk/osrm-backend/build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-Wno-error -w" -DCMAKE_CXX_FLAGS="-Wno-error -w"
    cmake --build . -j$(nproc) && cmake --build . --target install -j$(nproc)
else
    echo "osrm-backend/build directory already exists, skipping build"
fi

cd ~/disk/osrm_full_$DATE
cp -r ~/disk/osrm-backend/profiles/lib/ .

# Check if planet file exists and is less than a week old
PLANET_SOURCE_FILE=~/disk/planet-latest.osm.pbf
if [ -f "$PLANET_SOURCE_FILE" ]; then
    # Get file age in seconds
    FILE_AGE=$(($(date +%s) - $(stat -c %Y "$PLANET_SOURCE_FILE" 2>/dev/null || stat -f %m "$PLANET_SOURCE_FILE" 2>/dev/null)))
    # 7 days in seconds = 604800
    if [ "$FILE_AGE" -lt 604800 ]; then
        echo "Found recent planet file (less than 7 days old), copying from ~/disk/"
        cp "$PLANET_SOURCE_FILE" planet-latest.osm.pbf
    else
        echo "Planet file is older than 7 days, downloading new one"
        curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
        cp planet-latest.osm.pbf ~/disk/
    fi
else
    echo "No existing planet file found, downloading new one"
    curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
    cp planet-latest.osm.pbf ~/disk/
fi

date
~/disk/osrm-backend/build/osrm-extract -p bicycle.lua planet-latest.osm.pbf || echo "osrm-extract failed"
telegram-send "Extract finished $(hostname)"

cp -r ~/disk/osrm_full_$DATE ~/disk/osrm_full_extracted_$DATE

~/disk/osrm-backend/build/osrm-contract planet-latest.osrm --segment-speed-file traffic_final.csv || echo "osrm-contract failed"
telegram-send "Contract finished $(hostname)"

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))
echo "==========================================="
echo "Total script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "==========================================="

sudo chmod 644 planet-latest.osrm.fileIndex
date
rm planet-latest.osm.pbf
telegram-send "Finished osrm build $(hostname)"
echo "Processed: ~/disk/osrm_full_$DATE"

~/disk/osrm-backend/build/osrm-routed --algorithm ch planet-latest.osrm -p 8003