set -x

# Record start time
START_TIME=$(date +%s)

# Install osmium-tool if not present (requires sudo)
if ! command -v osmium &> /dev/null; then
    echo "osmium-tool not found. Please install it with: sudo apt install osmium-tool"
    exit 1
fi

HOSTNAME=$(hostname)

# Parse args: `full` triggers download+merge; `--profile road|gravel` selects the bike profile.
# Both are optional and may appear in any order (default: non-full, road).
PROFILE="road"
MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        full) MODE="full"; shift ;;
        *) echo "Unknown argument: $1"; shift ;;
    esac
done

# Profile-specific inputs/outputs. Road uses the asphalt-popularity traffic CSV and bicycle.lua;
# gravel uses the surface-aware CSV and gravel.lua. Separate output dirs so both graphs can coexist.
if [ "$PROFILE" = "gravel" ]; then
    LUA_FILE="gravel.lua"
    BUILD_DIR="osrm_merged_gravel"
    TRAFFIC_CSV="$HOME/disk/traffic_dumps/traffic_final_gravel.csv"
    ROUTED_PORT=8006
else
    LUA_FILE="bicycle.lua"
    BUILD_DIR="osrm_merged_road"
    TRAFFIC_CSV="$HOME/disk/traffic_dumps/traffic_final_road.csv"
    ROUTED_PORT=8005
fi
echo "Building merged graph: profile=$PROFILE build_dir=$BUILD_DIR lua=$LUA_FILE port=$ROUTED_PORT"

mkdir -p ~/disk/${BUILD_DIR}
cd ~/disk/${BUILD_DIR}
rm -rf ~/disk/${BUILD_DIR}/*
cp ~/data/AutoRouteServices/osrm/${LUA_FILE} .

# Track downloaded files
DOWNLOADED_FILES=()

# Function to download with retries (supports resume with -C -)
download_with_retry() {
    local url=$1
    local max_retries=5
    local retry_count=0
    local filename=$(basename "$url")

    while [ $retry_count -lt $max_retries ]; do
        echo "Downloading $url (attempt $((retry_count + 1))/$max_retries)..."
        # Use -C - to resume partial downloads, increase timeout for large files
        if curl -C - -OL --fail --retry 5 --retry-delay 10 --connect-timeout 30 --max-time 3600 "$url"; then
            if [ -s "$filename" ]; then
                echo "Successfully downloaded $filename"
                DOWNLOADED_FILES+=("$filename")
                return 0
            else
                echo "Downloaded file $filename is empty, retrying..."
                rm -f "$filename"
            fi
        else
            echo "Download failed for $url"
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Waiting 30 seconds before retry..."
            sleep 30
        fi
    done

    echo "WARNING: Failed to download $url after $max_retries attempts - skipping this file"
    rm -f "$filename"  # Remove any partial download
    return 1
}

if [ "$MODE" == "full" ]; then
    echo "Running full download and merge..."
    download_with_retry https://download.geofabrik.de/europe/cyprus-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/russia/northwestern-fed-district-latest.osm.pbf
    #UK parts
    download_with_retry https://download.geofabrik.de/europe/united-kingdom/england-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/europe/united-kingdom/scotland-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/europe/austria-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/europe/estonia-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/europe/serbia-latest.osm.pbf

    #Spain
    download_with_retry https://download.geofabrik.de/europe/spain/cataluna-latest.osm.pbf
    ##Germany
    download_with_retry https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf #Berlin
    download_with_retry https://download.geofabrik.de/europe/germany/bayern-latest.osm.pbf #Munich
    download_with_retry https://download.geofabrik.de/europe/germany/sachsen-latest.osm.pbf #Leipzig1
    download_with_retry https://download.geofabrik.de/europe/germany/sachsen-anhalt-latest.osm.pbf #Leipzig2
    download_with_retry https://download.geofabrik.de/europe/germany/thueringen-latest.osm.pbf #Leipzig3
    download_with_retry https://download.geofabrik.de/europe/germany/hessen-latest.osm.pbf
    download_with_retry https://download.geofabrik.de/europe/germany/rheinland-pfalz-latest.osm.pbf
    #Czech
#    download_with_retry https://download.geofabrik.de/europe/czech-republic-latest.osm.pbf
    ##North Americas
#    download_with_retry https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf
#    download_with_retry https://download.geofabrik.de/north-america/canada/ontario-latest.osm.pbf

    # Check if we have any files to merge
    if [ ${#DOWNLOADED_FILES[@]} -eq 0 ]; then
        echo "ERROR: No files were successfully downloaded!"
        exit 1
    fi

    echo "Merging ${#DOWNLOADED_FILES[@]} files: ${DOWNLOADED_FILES[*]}"
    osmium merge "${DOWNLOADED_FILES[@]}" -o merged.osm.pbf

    if [ ! -s merged.osm.pbf ]; then
        echo "ERROR: Merge failed or produced empty file!"
        exit 1
    fi

    ls -la merged.osm.pbf

    cd ~/disk/AutoRoute
    mvn compile && MAVEN_OPTS="-XX:+UseParallelGC -XX:MaxRAMPercentage=90" mvn exec:java -Dexec.mainClass="com.autoroute.osm.ModifyOsmWays" -Dexec.args="/home/$USER/disk/${BUILD_DIR}/merged.osm.pbf /home/$USER/data/AutoRouteServices/heigit/heygit_ids.txt"
    cd ~/disk/${BUILD_DIR}

    rm merged.osm.pbf
    mv merged-modified.osm.pbf merged.osm.pbf
    cp merged.osm.pbf ~/disk/
else
    echo "Copying merged.osm.pbf from ~/disk..."
    cp ~/disk/merged.osm.pbf .
    if [ ! -s merged.osm.pbf ]; then
        echo "ERROR: merged.osm.pbf not found in ~/disk or is empty!"
        exit 1
    fi
fi

cp -r ~/disk/osrm-backend/profiles/lib/ .
# bicycle.lua/gravel.lua are thin shims that require('lib/bike_common'); stock OSRM lib lacks it.
cp ~/data/AutoRouteServices/osrm/lib/bike_common.lua lib/
cp ~/disk/osrm-backend/data/driving_side.geojson .


~/disk/osrm-backend/build/osrm-extract --location-dependent-data driving_side.geojson -p ${LUA_FILE} merged.osm.pbf || echo "osrm-extract failed"
~/disk/osrm-backend/build/osrm-partition merged.osrm || echo "osrm-partition failed"

if [ ! -f "$TRAFFIC_CSV" ]; then echo "ERROR: traffic CSV not found: $TRAFFIC_CSV"; exit 1; fi
CUSTOMIZE_ARGS="--segment-speed-file $TRAFFIC_CSV"
#if [ -f ~/disk/traffic_dumps/traffic_final_turns.csv ]; then
#    CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file $HOME/disk/traffic_dumps/traffic_final_turns.csv"
#fi
~/disk/osrm-backend/build/osrm-customize merged.osrm $CUSTOMIZE_ARGS || echo "osrm-customize failed"

rm *.pbf
rm *.osrm.ebg *.osrm.cnbg *.osrm.cnbg_to_ebg *.osrm.enw *.osrm.turn_penalties_index *.osrm.restrictions

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))
echo "==========================================="
echo "Total script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "==========================================="
telegram-send "merged $PROFILE graph is ready $(hostname)"

rm -rf ~/disk/share/${BUILD_DIR}
cp -r ~/disk/${BUILD_DIR} ~/disk/share/${BUILD_DIR}
cd ~/disk/share/${BUILD_DIR}

#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005
#~/disk/osrm-backend/build/osrm-routed --algorithm mld --mmap on merged.osrm -p ${ROUTED_PORT}

echo 123