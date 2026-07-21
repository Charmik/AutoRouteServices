set -x
PROFILE="road"
if [ "$1" = "--profile" ]; then PROFILE="$2"; fi
if [ "$PROFILE" = "gravel" ]; then
  LUA_FILE="gravel.lua"
  OUT_DIR="${OSRM_GRAVEL_DATA_DIR:-$HOME/data/osrm_gravel}"
  # Gravel uses the surface-aware traffic CSV (no asphalt popularity boost). Produced by the same
  # TrafficDumpCsvTask run as the road CSV (traffic_dump_gravel.csv -> traffic_final_gravel.csv).
else
  LUA_FILE="bicycle.lua"
  if [ -z "$OSRM_DATA_DIR" ]; then
      echo "ERROR: OSRM_DATA_DIR is not set"
      exit 1
  fi
  OUT_DIR="$OSRM_DATA_DIR"
fi
# Every traffic CSV is profile-suffixed: traffic_final_road.csv / traffic_final_gravel.csv.
TRAFFIC_CSV_NAME="traffic_final_${PROFILE}.csv"
TRAFFIC_CSV="$GEOFABRIC_DIR/traffic_dumps/$TRAFFIC_CSV_NAME"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR" || exit
rm -rf "$OUT_DIR"/*
cp "$AUTOROUTE_SERVICES_DIR/osrm/$LUA_FILE" "$GEOFABRIC_DIR"
cp "$GEOFABRIC_DIR/$LUA_FILE" "$GEOFABRIC_DIR/merged.osm.pbf" "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" .
# Stage the profile's traffic CSV under its own name, so the build dir shows which profile it came from.
if [ ! -f "$TRAFFIC_CSV" ]; then echo "ERROR: traffic CSV not found: $TRAFFIC_CSV"; exit 1; fi
cp "$TRAFFIC_CSV" .
#if [ -f "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" ]; then
#    cp "$GEOFABRIC_DIR/traffic_dumps/traffic_final_turns.csv" .
#fi
cp -r "$OSRM_SOURCES/profiles/lib" .
cp "$AUTOROUTE_SERVICES_DIR/osrm/lib/bike_common.lua" lib/
cp "$OSRM_SOURCES/data/driving_side.geojson" .

"$OSRM_SOURCES/build/osrm-extract" --location-dependent-data driving_side.geojson -p "$LUA_FILE" merged.osm.pbf || echo "osrm-extract failed"
"$OSRM_SOURCES/build/osrm-partition" merged.osrm || echo "osrm-partition failed"
CUSTOMIZE_ARGS="--segment-speed-file $TRAFFIC_CSV_NAME"
#if [ -f traffic_final_turns.csv ]; then
#    CUSTOMIZE_ARGS="$CUSTOMIZE_ARGS --turn-penalty-file traffic_final_turns.csv"
#fi
"$OSRM_SOURCES/build/osrm-customize" merged.osrm --segment-speed-file "$TRAFFIC_CSV_NAME" || echo "osrm-customize failed"
#"$OSRM_SOURCES/build/osrm-customize" merged.osrm --segment-speed-file "$TRAFFIC_CSV_NAME" --turn-penalty-file traffic_final_turns.csv || echo "osrm-customize failed"
