#!/bin/bash
set -x
#sudo apt-get install -y osmium-tool

# Parse arguments
# $1 (required): part1, part2, or both
# $2 (required): mld or ch - which OSRM algorithm to build
# $3 (optional): full - when provided, download files and run osmium + ModifyOsmWays

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <part1|part2|both> <mld|ch> [full]"
    echo "  part1|part2|both - which parts to process (required)"
    echo "  mld|ch - OSRM algorithm: mld (partition+customize) or ch (contract) (required)"
    echo "  full - download files and run osmium + ModifyOsmWays (optional)"
    exit 1
fi

PART="$1"
ALGORITHM="$2"
FULL_MODE="$3"

if [ "$PART" != "part1" ] && [ "$PART" != "part2" ] && [ "$PART" != "both" ]; then
    echo "Error: first argument must be 'part1', 'part2', or 'both'"
    exit 1
fi

if [ "$ALGORITHM" != "mld" ] && [ "$ALGORITHM" != "ch" ]; then
    echo "Error: second argument must be 'mld' or 'ch'"
    exit 1
fi

if [ -n "$FULL_MODE" ] && [ "$FULL_MODE" != "full" ]; then
    echo "Error: third argument must be 'full' or empty"
    exit 1
fi

DO_PART1=false
DO_PART2=false
if [ "$PART" = "part1" ] || [ "$PART" = "both" ]; then
    DO_PART1=true
fi
if [ "$PART" = "part2" ] || [ "$PART" = "both" ]; then
    DO_PART2=true
fi

mkdir -p ~/disk

START_TIME=$(date +%s)
DATE=$(date +%d.%m.%Y)
BASE_DIR=~/disk/osrm_${DATE}_${ALGORITHM}
date
telegram-send "Started osrm split build $PART $ALGORITHM $(hostname)"
cd ~/disk

# Build OSRM backend if needed
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

# Create working directories based on which parts we're processing
cd ~/disk
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"
cp -r ~/data/AutoRouteServices/osrm "$BASE_DIR/osrm_scripts" # for history - to see which scripts we ran

if [ "$DO_PART1" = true ]; then
    mkdir -p "$BASE_DIR/part1"
    cp ~/data/AutoRouteServices/osrm/bicycle.lua "$BASE_DIR/part1/"
fi

if [ "$DO_PART2" = true ]; then
    mkdir -p "$BASE_DIR/part2"
    cp ~/data/AutoRouteServices/osrm/bicycle.lua "$BASE_DIR/part2/"
fi

# Download and process PBF files only in full mode
if [ "$FULL_MODE" = "full" ]; then
    # Check that AutoRoute compiles before downloading large files
    echo "Checking AutoRoute compilation..."
    cd ~/disk/AutoRoute
    if ! mvn compile; then
        telegram-send "AutoRoute compilation failed $(hostname)"
        exit 1
    fi
    echo "AutoRoute compilation successful"

    cd ~/disk

    #mkdir ~/disk/traffic_dumps
    #rsync -r --progress charm@88.99.161.250:/home/charm/disk/traffic_dumps/traffic_final.csv ~/disk/traffic_dumps/

    if [ "$DO_PART1" = true ]; then
        echo "Downloading Part 1 regions..."
        wget -N https://download.geofabrik.de/europe-latest.osm.pbf
        wget -N https://download.geofabrik.de/asia-latest.osm.pbf
        wget -N https://download.geofabrik.de/africa-latest.osm.pbf

        echo "Merging Part 1 regions..."
        osmium merge europe-latest.osm.pbf asia-latest.osm.pbf africa-latest.osm.pbf -o ~/disk/planet-part1.osm.pbf
        cd ~/disk/AutoRoute
        MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/planet-part1.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt" || { telegram-send "ModifyOsmWays part1 failed $(hostname)"; exit 1; }
    fi

    if [ "$DO_PART2" = true ]; then
        cd ~/disk
        echo "Downloading Part 2 regions..."
        wget -N https://download.geofabrik.de/north-america-latest.osm.pbf
        wget -N https://download.geofabrik.de/south-america-latest.osm.pbf
        wget -N https://download.geofabrik.de/australia-oceania-latest.osm.pbf

        echo "Merging Part 2 regions..."
        osmium merge north-america-latest.osm.pbf south-america-latest.osm.pbf australia-oceania-latest.osm.pbf -o ~/disk/planet-part2.osm.pbf
        cd ~/disk/AutoRoute
        MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/planet-part2.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt" || { telegram-send "ModifyOsmWays part2 failed $(hostname)"; exit 1; }
    fi
else
    echo "Skipping download and osmium merge (not in full mode)"
fi

# Function to setup and process a part
# Usage: process_part <part_number>
process_part() {
    local part_num=$1
    local part_dir="$BASE_DIR/part${part_num}"
    local pbf_file=planet-part${part_num}-modified.osm.pbf
    local osrm_file=planet-part${part_num}-modified.osrm

    echo "Setting up Part ${part_num}..."
    cd "$part_dir"
    cp -r ~/disk/osrm-backend/profiles/lib/ .
    cp ~/disk/osrm-backend/data/driving_side.geojson .
    ln -s ~/disk/${pbf_file} ./${pbf_file}

    echo "Extracting Part ${part_num}..."
    ~/disk/osrm-backend/build/osrm-extract -t $(nproc) --location-dependent-data driving_side.geojson -p bicycle.lua ${pbf_file} || { echo "osrm-extract part${part_num} failed"; telegram-send "osrm-extract part${part_num} failed $(hostname)"; exit 1; }
    #telegram-send "Part ${part_num} extract finished $(hostname)"

    if [ "$ALGORITHM" = "mld" ]; then
        ~/disk/osrm-backend/build/osrm-partition -t $(nproc) ${osrm_file} || { echo "osrm-partition part${part_num} failed"; telegram-send "osrm-partition part${part_num} failed $(hostname)"; exit 1; }
        #telegram-send "Part ${part_num} partition finished $(hostname)"
        CUSTOMIZE_ARGS="--segment-speed-file ~/disk/traffic_dumps/traffic_final.csv"
        if [ -f ~/disk/traffic_dumps/traffic_final_turns.csv ]; then
            CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file ~/disk/traffic_dumps/traffic_final_turns.csv"
        fi
        ~/disk/osrm-backend/build/osrm-customize -t $(nproc) ${osrm_file} $CUSTOMIZE_ARGS || { echo "osrm-customize part${part_num} failed"; telegram-send "osrm-customize part${part_num} failed $(hostname)"; exit 1; }
    else
        ~/disk/osrm-backend/build/osrm-contract -t $(nproc) ${osrm_file} --segment-speed-file ~/disk/traffic_dumps/traffic_final.csv || { echo "osrm-contract part${part_num} failed"; telegram-send "osrm-contract part${part_num} failed $(hostname)"; exit 1; }
    fi
    rm *.osrm.ebg *.osrm.cnbg *.osrm.cnbg_to_ebg *.osrm.enw *.osrm.turn_penalties_index *.osrm.restrictions
    telegram-send "Part ${part_num} $ALGORITHM finished $(hostname)"
}

if [ "$DO_PART1" = true ]; then
    process_part 1
fi

if [ "$DO_PART2" = true ]; then
    process_part 2
fi

# Calculate execution time
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))
echo "==========================================="
echo "Total script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "==========================================="

date
#telegram-send "Finished osrm split build $PART $ALGORITHM $(hostname)"

echo "Output directory: $BASE_DIR"
if [ "$DO_PART1" = true ]; then
    echo "  Processed Part 1: $BASE_DIR/part1"
fi
if [ "$DO_PART2" = true ]; then
    echo "  Processed Part 2: $BASE_DIR/part2"
fi

# Start routing server for a part
# Usage: start_server <part_number> <port> <memory_max>
start_server() {
    local part_num=$1
    local port=$2
    local mem_max=$3
    local part_dir="$BASE_DIR/part${part_num}"
    local osrm_file=planet-part${part_num}-modified.osrm

    cd "$part_dir"
    systemd-run --user --scope -p MemoryMax=${mem_max} -p MemorySwapMax=10 ~/disk/osrm-backend/build/osrm-routed --algorithm ${ALGORITHM} ${osrm_file} -p ${port}
    #systemd-run --user --scope -p MemoryMax=160G -p MemorySwapMax=10 ~/disk/osrm-backend/build/osrm-routed --algorithm CH planet-part1-modified.osrm -p 8003
    #systemd-run --user --scope -p MemoryMax=70G -p MemorySwapMax=10 ~/disk/osrm-backend/build/osrm-routed --algorithm CH planet-part2-modified.osrm -p 8003
}

if [ "$DO_PART1" = true ]; then
    start_server 1 8003 160G
fi
if [ "$DO_PART2" = true ]; then
    start_server 2 8003 70G
fi