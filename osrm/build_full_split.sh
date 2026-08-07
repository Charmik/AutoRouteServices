#!/bin/bash
set -x
#sudo apt-get install -y osmium-tool

# Parse arguments
# $1 (required): part1, part2, or both
# $2 (required): mld or ch - which OSRM algorithm to build
# $3 (optional): full - when provided, download files and run osmium + ModifyOsmWays
# --profile road|gravel (required, may appear anywhere): which bike profile to build

#/home/charm/disk/osrm-backend/build/osrm-contract -t 12 planet-part1-modified.osrm --segment-speed-file /home/charm/disk/traffic_dumps/traffic_final_gravel.csv
#cd ~/data
#sudo swapoff -a
#rm -f swap
#sudo fallocate -l 750G swap # 256RAM + 440 is not enough for extract
#sudo chmod 600 swap
#sudo mkswap swap
#sudo swapon swap
#echo '/home/remote1/disk/swap none swap sw 0 0' | sudo tee -a /etc/fstab
#sudo swapon -p 32767 swap
#sudo swapon -p 1 swap
#sudo systemctl stop systemd-oomd
#sudo systemctl stop systemd-oomd.socket

PROFILE=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE="$2"; shift; shift ;; # two shifts, not `shift 2`: a bare trailing --profile would loop forever
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$PROFILE" ]; then
    echo "Usage: $0 <part1|part2|both> <mld|ch> [full] --profile <road|gravel>"
    echo "  part1|part2|both - which parts to process (required)"
    echo "  mld|ch - OSRM algorithm: mld (partition+customize) or ch (contract) (required)"
    echo "  full - download files and run osmium + ModifyOsmWays (optional)"
    echo "  --profile road|gravel - bike profile to build (required)"
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

if [ "$PROFILE" != "road" ] && [ "$PROFILE" != "gravel" ]; then
    echo "Error: --profile must be 'road' or 'gravel'"
    exit 1
fi

# Profile-specific inputs/outputs. Road uses the asphalt-popularity traffic CSV and bicycle.lua;
# gravel uses the surface-aware CSV and gravel.lua. Separate output dirs so both graphs can coexist.
if [ "$PROFILE" = "gravel" ]; then
    LUA_FILE="gravel.lua"
    TRAFFIC_CSV="$HOME/disk/traffic_dumps/traffic_final_gravel.csv"
    ROUTED_PORT=8004
    # gravel keeps unpaved ways too, so the graph is bigger: +15G over road
    PART1_MEM=175G
    PART2_MEM=85G
else
    LUA_FILE="bicycle.lua"
    TRAFFIC_CSV="$HOME/disk/traffic_dumps/traffic_final_road.csv"
    ROUTED_PORT=8003
    PART1_MEM=160G
    PART2_MEM=70G
fi
echo "Building split graph: profile=$PROFILE lua=$LUA_FILE traffic=$TRAFFIC_CSV port=$ROUTED_PORT"

# Checked up front: extract/partition take hours, no point starting without the speed file.
if [ ! -f "$TRAFFIC_CSV" ]; then
    echo "ERROR: traffic CSV not found: $TRAFFIC_CSV"
    exit 1
fi

# Verify a .pbf file exists and is at least the given size in GB
# Usage: check_pbf_size <file> <min_gb>
check_pbf_size() {
    local file=$1
    local min_gb=$2
    if [ ! -f "$file" ]; then
        echo "Error: $file does not exist"
        telegram-send "pbf check failed: $file missing $(hostname)"
        exit 1
    fi
    local size_bytes
    size_bytes=$(stat -c%s "$file")
    local min_bytes=$((min_gb * 1024 * 1024 * 1024))
    if [ "$size_bytes" -lt "$min_bytes" ]; then
        local size_gb=$((size_bytes / 1024 / 1024 / 1024))
        echo "Error: $file is ${size_gb}GB, expected > ${min_gb}GB"
        telegram-send "pbf check failed: $file is ${size_gb}GB, expected > ${min_gb}GB $(hostname)"
        exit 1
    fi
    echo "OK: $file size check passed (> ${min_gb}GB)"
}

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
BASE_DIR=~/disk/osrm_${DATE}_${ALGORITHM}_${PROFILE}
# Pristine post-extract snapshot, see snapshot_extract() below.
EXTRACT_DIR=${BASE_DIR}_extract
date
telegram-send "Started osrm split build $PART $ALGORITHM $PROFILE $(hostname)"
cd ~/disk

# Build OSRM backend if needed
cd ~/disk
if [ ! -d "osrm-backend/build" ]; then
    rm -rf osrm-backend
    git clone https://github.com/Charmik/osrm-backend.git
    cd ~/disk/osrm-backend
#    git checkout fix-segfaults-asserts-hacks
    git checkout master_fresh_with_compact_fix
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
    cp ~/data/AutoRouteServices/osrm/${LUA_FILE} "$BASE_DIR/part1/"
fi

if [ "$DO_PART2" = true ]; then
    mkdir -p "$BASE_DIR/part2"
    cp ~/data/AutoRouteServices/osrm/${LUA_FILE} "$BASE_DIR/part2/"
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
    #rsync -r --progress charm@88.99.161.250:/home/charm/disk/traffic_dumps/traffic_final_road.csv ~/disk/traffic_dumps/

    if [ "$DO_PART1" = true ]; then
        echo "Downloading Part 1 regions..."
        wget -N https://download.geofabrik.de/europe-latest.osm.pbf
        wget -N https://download.geofabrik.de/asia-latest.osm.pbf
        wget -N https://download.geofabrik.de/africa-latest.osm.pbf

        echo "Merging Part 1 regions..."
        osmium merge --overwrite europe-latest.osm.pbf asia-latest.osm.pbf africa-latest.osm.pbf -o ~/disk/planet-part1.osm.pbf || { echo "osmium merge part1 failed"; telegram-send "osmium merge part1 failed $(hostname)"; exit 1; }
        check_pbf_size ~/disk/planet-part1.osm.pbf 50
        cd ~/disk/AutoRoute
        MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/planet-part1.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt" || { telegram-send "ModifyOsmWays part1 failed $(hostname)"; exit 1; }
        check_pbf_size ~/disk/planet-part1-modified.osm.pbf 70
    fi

    if [ "$DO_PART2" = true ]; then
        cd ~/disk
        echo "Downloading Part 2 regions..."
        wget -N https://download.geofabrik.de/north-america-latest.osm.pbf
        wget -N https://download.geofabrik.de/south-america-latest.osm.pbf
        wget -N https://download.geofabrik.de/australia-oceania-latest.osm.pbf

        echo "Merging Part 2 regions..."
        osmium merge --overwrite north-america-latest.osm.pbf south-america-latest.osm.pbf australia-oceania-latest.osm.pbf -o ~/disk/planet-part2.osm.pbf || { echo "osmium merge part2 failed"; telegram-send "osmium merge part2 failed $(hostname)"; exit 1; }
        check_pbf_size ~/disk/planet-part2.osm.pbf 20
        cd ~/disk/AutoRoute
        MAVEN_OPTS="-XX:+UseParallelGC -Xmx150g" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/planet-part2.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt" || { telegram-send "ModifyOsmWays part2 failed $(hostname)"; exit 1; }
        check_pbf_size ~/disk/planet-part2-modified.osm.pbf 30
    fi
else
    echo "Skipping download and osmium merge (not in full mode)"
fi

# Save a pristine copy of a part right after extract, before any speed file is applied.
# osrm-contract/osrm-customize run the updater, which rewrites .osrm.geometry in place with the
# traffic CSV applied *before* contraction/customization starts. The `*` and `/` tokens in the CSV
# are relative to the current speed, so re-running on an already-updated graph double-applies them
# (a /10 penalty becomes /100). If contract/customize crashes, restore from here and re-run instead
# of re-extracting:
#   rm -rf $BASE_DIR/partN && cp -a ${EXTRACT_DIR}/partN $BASE_DIR/
# Usage: snapshot_extract <part_number>
snapshot_extract() {
    local part_num=$1
    local part_dir="$BASE_DIR/part${part_num}"
    local dest="$EXTRACT_DIR/part${part_num}"

    echo "Snapshotting post-extract Part ${part_num} to ${dest}..."
    mkdir -p "$EXTRACT_DIR"
    rm -rf "$dest"
    cp -r "$part_dir" "$dest" || { echo "extract snapshot part${part_num} failed"; telegram-send "extract snapshot part${part_num} failed $(hostname)"; exit 1; }
}

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
    # bicycle.lua/gravel.lua are thin shims that require('lib/bike_common'); stock OSRM lib lacks it.
    cp ~/data/AutoRouteServices/osrm/lib/bike_common.lua lib/
    cp ~/disk/osrm-backend/data/driving_side.geojson .
    ln -s ~/disk/${pbf_file} ./${pbf_file}

    echo "Extracting Part ${part_num}..."
    ~/disk/osrm-backend/build/osrm-extract -t $(nproc) --location-dependent-data driving_side.geojson -p ${LUA_FILE} ${pbf_file} || { echo "osrm-extract part${part_num} failed"; telegram-send "osrm-extract part${part_num} failed $(hostname)"; exit 1; }
    #telegram-send "Part ${part_num} extract finished $(hostname)"

    snapshot_extract ${part_num}

    if [ "$ALGORITHM" = "mld" ]; then
        ~/disk/osrm-backend/build/osrm-partition -t $(nproc) ${osrm_file} || { echo "osrm-partition part${part_num} failed"; telegram-send "osrm-partition part${part_num} failed $(hostname)"; exit 1; }
        #telegram-send "Part ${part_num} partition finished $(hostname)"
        CUSTOMIZE_ARGS="--segment-speed-file $TRAFFIC_CSV"
#        if [ -f $HOME/disk/traffic_dumps/traffic_final_turns.csv ]; then
#            CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file $HOME/disk/traffic_dumps/traffic_final_turns.csv"
#        fi
        ~/disk/osrm-backend/build/osrm-customize -t $(nproc) ${osrm_file} $CUSTOMIZE_ARGS || { echo "osrm-customize part${part_num} failed - do NOT re-run on this dir, restore first: rm -rf $part_dir && cp -a $EXTRACT_DIR/part${part_num} $BASE_DIR/"; telegram-send "osrm-customize part${part_num} failed $(hostname)"; exit 1; }
    else
        ~/disk/osrm-backend/build/osrm-contract -t $(nproc) ${osrm_file} --segment-speed-file "$TRAFFIC_CSV" || { echo "osrm-contract part${part_num} failed - do NOT re-run on this dir, restore first: rm -rf $part_dir && cp -a $EXTRACT_DIR/part${part_num} $BASE_DIR/"; telegram-send "osrm-contract part${part_num} failed $(hostname)"; exit 1; }
    fi
    rm *.osrm.ebg *.osrm.cnbg *.osrm.cnbg_to_ebg *.osrm.enw *.osrm.turn_penalties_index *.osrm.restrictions
    telegram-send "Part ${part_num} $ALGORITHM $PROFILE finished $(hostname)"
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
    start_server 1 ${ROUTED_PORT} ${PART1_MEM}
fi
if [ "$DO_PART2" = true ]; then
    start_server 2 ${ROUTED_PORT} ${PART2_MEM}
fi