set -x

# Record start time
START_TIME=$(date +%s)

apt install osmium-tool

HOSTNAME=$(hostname)
BUILD_DIR="osrm_merged"
mkdir -p ~/disk/share/${BUILD_DIR}
cd ~/disk/share/${BUILD_DIR}
rm -rf ~/disk/share/${BUILD_DIR}/*
cp ~/data/AutoRouteServices/osrm/bicycle.lua .

# Function to download with retries
download_with_retry() {
    local url=$1
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        echo "Downloading $url (attempt $((retry_count + 1))/$max_retries)..."
        if curl -OL --fail --retry 3 --retry-delay 5 --retry-max-time 120 "$url"; then
            local filename=$(basename "$url")
            if [ -s "$filename" ]; then
                echo "Successfully downloaded $filename"
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
            echo "Waiting 10 seconds before retry..."
            sleep 10
        fi
    done

    echo "Failed to download $url after $max_retries attempts"
    return 1
}

# Download all files with retry logic
download_with_retry https://download.geofabrik.de/europe/cyprus-latest.osm.pbf
download_with_retry https://download.geofabrik.de/russia/northwestern-fed-district-latest.osm.pbf
download_with_retry https://download.geofabrik.de/europe/united-kingdom-latest.osm.pbf
download_with_retry https://download.geofabrik.de/europe/germany-latest.osm.pbf
download_with_retry https://download.geofabrik.de/europe/austria-latest.osm.pbf
download_with_retry https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf
download_with_retry https://download.geofabrik.de/europe/czech-republic-latest.osm.pbf
download_with_retry https://download.geofabrik.de/north-america/canada/ontario-latest.osm.pbf
#download_with_retry https://download.geofabrik.de/europe/switzerland-latest.osm.pbf
#download_with_retry https://download.geofabrik.de/europe/denmark-latest.osm.pbf
#download_with_retry https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf
#https://download.geofabrik.de/asia/india/central-zone-latest.osm.pbf
#https://download.geofabrik.de/asia/india/northern-zone-latest.osm.pbf

osmium merge *pbf -o merged.osm.pbf
ls -la merged.osm.pbf

cp ~/disk/traffic_dumps/traffic_final.csv .
cp -r ~/disk/osrm-backend/profiles/lib/ .

~/disk/osrm-backend/build/osrm-extract -p bicycle.lua merged.osm.pbf || echo "osrm-extract failed"
~/disk/osrm-backend/build/osrm-contract merged.osrm --segment-speed-file traffic_final.csv || echo "osrm-contract failed"
rm *.pbf
#rm traffic_final.csv

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))
echo "==========================================="
echo "Total script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo "==========================================="

~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005

echo 123