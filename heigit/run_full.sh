#./download_heyGIT.sh
#./merge_json_files.sh ~/disk/share/heigit_road_surface_data

cd ~/disk
rm heygit_ids.txt
echo "start grep surface from all_roads"
grep "\"surface\": null" ~/disk/share/heigit_road_surface_data/all_roads.geojson | grep "\"combined_surface_osm_priority\": \"paved\"" | grep -Eo '"osm_id": [0-9]+\.[0-9]+' | awk '{print $2 " paved"}' | sed 's/\.0 / /' | sort -u > heygit_ids.txt

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
    #cp planet-latest.osm.pbf ~/disk/
fi

pip3 install --break-system-packages osmium
python3 ~/data/AutoRouteServices/heigit/modify_osm_ways.py ~/disk/planet-latest.osm.pbf ~/disk/heygit_ids.txt