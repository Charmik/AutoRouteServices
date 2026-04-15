set -x
if [ -z "$OSRM_DATA_DIR" ]; then
    echo "ERROR: OSRM_DATA_DIR is not set"
    exit 1
fi
mkdir -p $OSRM_DATA_DIR
cd $OSRM_DATA_DIR || exit
rm -rf $OSRM_DATA_DIR/*
cp "$AUTOROUTE_SERVICES_DIR/osrm/bicycle.lua" "$GEOFABRIC_DIR"                                                                                                                                                                                                                                                     
cp "$GEOFABRIC_DIR/bicycle.lua" "$GEOFABRIC_DIR/merged.osm.pbf" "$GEOFABRIC_DIR/traffic_dumps/traffic_final.csv" "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" .
#if [ -f "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" ]; then
#    cp "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" .
#fi
cp -r "$OSRM_SOURCES/profiles/lib" .
cp "$OSRM_SOURCES/data/driving_side.geojson" .

"$OSRM_SOURCES/build/osrm-extract" --location-dependent-data driving_side.geojson -p bicycle.lua merged.osm.pbf || echo "osrm-extract failed"
"$OSRM_SOURCES/build/osrm-partition" merged.osrm || echo "osrm-partition failed"
CUSTOMIZE_ARGS="--segment-speed-file traffic_final.csv"
if [ -f traffic_final_turns.csv ]; then
    CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file traffic_final_turns.csv"
fi
#"$OSRM_SOURCES/build/osrm-customize" merged.osrm --segment-speed-file traffic_final.csv || echo "osrm-customize failed"
"$OSRM_SOURCES/build/osrm-customize" merged.osrm --segment-speed-file traffic_final.csv --turn-penalty-file traffic_final_turns.csv || echo "osrm-customize failed"