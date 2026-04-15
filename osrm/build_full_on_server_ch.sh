#!/bin/bash
set -x
#sudo apt-get install -y htop vim tmux

mkdir ~/disk

#run_oom_protected() {
#    sudo bash -c "echo -17 > /proc/\$\$/oom_score_adj && exec sudo -u $USER $*"
#}

START_TIME=$(date +%s)
DATE=$(date +%d.%m.%Y)
date
telegram-send "Started osrm build $(hostname)"

#sudo swapoff -a
#rm -f swap
sudo fallocate -l 850G swap # 256RAM + 440 is not enough for extract
sudo chmod 600 swap
sudo mkswap swap
sudo swapon swap
#sudo swapon -p 32767 swap
#sudo swapon -p 1 swap

#sudo apt install -y build-essential git cmake pkg-config libbz2-dev libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libtbb-dev

cd ~/disk
rm -rf osrm_full_$DATE
mkdir osrm_full_$DATE
cd osrm_full_$DATE

cp ~/data/AutoRouteServices/osrm/bicycle.lua .
#rsync -r --progress charm@88.99.161.250:/home/charm/data/AutoRouteServices/osrm/bicycle.lua .

#rsync -r --progress charm@88.99.161.250:/home/charm/disk/traffic_dumps/traffic_final.csv .
#cp ~/data/traffic_dumps/traffic_final.csv .

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

#    cmake .. \
#        -DCMAKE_BUILD_TYPE=Release \
#        -DCMAKE_C_COMPILER=gcc-13 \
#        -DCMAKE_CXX_COMPILER=g++-13 \
#        -DCMAKE_POLICY_DEFAULT_CMP0144=NEW \
#        -DBOOST_ROOT=/home/user/disk/boost_1_81 \
#        -DTBB_DIR=/home/user/disk/tbb_2021/lib/cmake/TBB \
#        -DTBB_INCLUDE_DIR=/home/user/disk/tbb_2021/include \
#        -DCMAKE_PREFIX_PATH="/home/user/disk/tbb_2021;/home/user/disk/boost_1_81" \
#        -DCMAKE_CXX_FLAGS="-Wno-unused-but-set-variable -Wno-error=unused-but-set-variable -Wno-error=uninitialized"
#
#      cmake --build . -j16
else
    echo "osrm-backend/build directory already exists, skipping build"
fi


cd ~/disk/osrm_full_$DATE
cp -r ~/disk/osrm-backend/profiles/lib/ .
cp ~/disk/osrm-backend/data/driving_side.geojson .

# Check if planet file exists and is less than a week old
#PLANET_SOURCE_FILE=~/disk/planet-latest.osm.pbf
#if [ -f "$PLANET_SOURCE_FILE" ]; then
#    # Get file age in seconds
#    FILE_AGE=$(($(date +%s) - $(stat -c %Y "$PLANET_SOURCE_FILE" 2>/dev/null || stat -f %m "$PLANET_SOURCE_FILE" 2>/dev/null)))
#    # 7 days in seconds = 604800
#    if [ "$FILE_AGE" -lt 604800 ]; then
#        echo "Found recent planet file (less than 7 days old), copying from ~/disk/"
#        cp "$PLANET_SOURCE_FILE" planet-latest.osm.pbf
#    else
#        echo "Planet file is older than 7 days, downloading new one"
#        curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
#        cp planet-latest.osm.pbf ~/disk/
#    fi
#else
#    echo "No existing planet file found, downloading new one"
#    curl -OL https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
#    cp planet-latest.osm.pbf ~/disk/
#fi

#cd ~/disk/AutoRoute
mkdir logs
#mvn compile && MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/planet-latest.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt"
#mvn compile && MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/eurasia/planet-latest.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt"
#telegram-send "ModifyOsmWays finished $(hostname)"

cp ~/disk/planet-latest-modified.osm.pbf ~/disk/osrm_full_$DATE/planet-latest.osm.pbf

date
#telegram-send "Waiting to run sudo $(hostname)"
~/disk/osrm-backend/build/osrm-extract -t $(nproc) --location-dependent-data driving_side.geojson -p bicycle.lua planet-latest.osm.pbf || { echo "osrm-extract failed"; telegram-send "osrm-extract failed $(hostname)"; exit 1; }
telegram-send "Extract finished $(hostname)"

rm planet-latest.osm.pbf # rm after extract not to copy .pbf to other directories

# USE FOR CH
#rm -rf ~/disk/osrm_full_extracted_$DATE
#cp -r ~/disk/osrm_full_$DATE ~/disk/osrm_full_extracted_$DATE

#telegram-send "Waiting to run sudo $(hostname)"
#~/disk/osrm-backend/build/osrm-contract planet-latest.osrm --segment-speed-file ~/data/traffic_dumps/traffic_final.csv || echo "osrm-contract failed"
#telegram-send "Contract finished $(hostname)"

~/disk/osrm-backend/build/osrm-partition -t $(nproc) --max-cell-sizes=1024,16384,262144,4194304 planet-latest.osrm || { echo "osrm-partition failed"; telegram-send "osrm-partition failed $(hostname)"; exit 1; }
telegram-send "Partition finished $(hostname)"

rm -rf ~/disk/osrm_full_partition_$DATE
cp -r ~/disk/osrm_full_$DATE ~/disk/osrm_full_partition_$DATE

CUSTOMIZE_ARGS="--segment-speed-file ~/disk/traffic_dumps/traffic_final.csv"
if [ -f ~/disk/traffic_dumps/traffic_final_turns.csv ]; then
    CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file ~/disk/traffic_dumps/traffic_final_turns.csv"
fi
~/disk/osrm-backend/build/osrm-customize -t $(nproc) planet-latest.osrm $CUSTOMIZE_ARGS || { echo "osrm-customize failed"; telegram-send "osrm-customize failed $(hostname)"; exit 1; }
#~/disk/osrm-backend/build/osrm-customize -t $(nproc) planet-latest.osrm || { echo "osrm-customize failed"; telegram-send "osrm-customize failed $(hostname)"; exit 1; }
telegram-send "Customize finished $(hostname)"


END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))
echo "==========================================="
echo "Total script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "==========================================="

rm planet-latest.osm.pbf
date
sudo chmod 644 planet-latest.osrm.fileIndex

telegram-send "Finished osrm build $(hostname)"
echo "Processed: ~/data/osrm_full_$DATE"

#~/disk/osrm-backend/build/osrm-routed --algorithm ch planet-latest.osrm -p 8003
systemd-run --user --scope -p MemoryMax=200G -p MemorySwapMax=10 ~/disk/osrm-backend/build/osrm-routed --algorithm mld planet-latest.osrm -p 8003