#!/bin/bash

# Log file setup
#LOG_DIR="/home/charm/data/backed_health_logs"
if [ $# -ne 1 ]; then
    echo "Usage: $0 [test|prod]"
    exit 1
fi

ENV=$1

case $ENV in
    "test")
        SERVER_IP="88.99.161.250"
        TELEGRAM_CONFIG="group_test.conf"
        SLEEP_BETWEEN_TIME=30
        ;;
    "prod")
        SERVER_IP="65.21.136.166"
        TELEGRAM_CONFIG="group_prod.conf"
        SLEEP_BETWEEN_TIME=120
        ;;
    *)
        echo "Error: Environment must be 'test' or 'prod'"
        exit 1
        ;;
esac

LOG_DIR="."
LOG_FILE="$LOG_DIR/route-check-$(date +%Y%m%d).log"
STATE_FILE="$LOG_DIR/route-check-state-$ENV.txt"

echo "Setting up $ENV environment..."
echo "IP: $SERVER_IP"
echo "TELEGRAM_CONFIG: $TELEGRAM_CONFIG"
echo "STATE_FILE: $STATE_FILE"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  echo "$1"
}

# Check previous state
check_previous_state() {
  if [ -f "$STATE_FILE" ]; then
    PREVIOUS_STATE=$(cat "$STATE_FILE")
    echo "$PREVIOUS_STATE"
  else
    echo "OK"  # Default to OK if no state file exists
  fi
}

# Update state
update_state() {
  echo "$1" > "$STATE_FILE"
}

# Function to generate a small random offset between 0.000001 and 0.001
generate_random_offset() {
  # Generate a random number between 1 and 1000
  local RANDOM_NUM=$((RANDOM % 1000 + 1))
  # Convert to an offset between 0.000001 and 0.001
  echo "scale=9; $RANDOM_NUM / 1000000" | bc
}

# Function to generate random coordinates within valid ranges
generate_random_coordinates() {
  # Generate random latitude between -90 and 90
  local LAT=$(echo "scale=9; (($RANDOM * 180) / 32767) - 90" | bc)

  # Generate random longitude between -180 and 180
  local LON=$(echo "scale=9; (($RANDOM * 360) / 32767) - 180" | bc)

  # Return the coordinates
  echo "$LAT $LON"
}

# Function to check a location
checkLocation() {
  local LAT=$1
  local LON=$2
  local MIN_DISTANCE=$3
  local MAX_DISTANCE=$4
  local LOCATION_NAME=${5:-"unnamed location"}  # Optional name parameter
  local WAIT_TIME=$6  # Required wait time parameter
  
  # Check if WAIT_TIME is provided
  if [ -z "$WAIT_TIME" ]; then
    log "ERROR: WAIT_TIME parameter not provided for $LOCATION_NAME"
    /home/charm/.local/bin/telegram-send --config $TELEGRAM_CONFIG "ERROR: WAIT_TIME parameter missing for location $LOCATION_NAME"
    return 1
  fi
  
  # Double wait time for test environment
  if [ "$ENV" = "test" ]; then
    WAIT_TIME=$((WAIT_TIME * 2))
  fi

  # Add small random offsets to coordinates
  local LAT_OFFSET=$(generate_random_offset)
  local LON_OFFSET=$(generate_random_offset)

  # Randomly decide if offset should be positive or negative
  if [ $((RANDOM % 2)) -eq 0 ]; then
    LAT_OFFSET="-$LAT_OFFSET"
  fi
  if [ $((RANDOM % 2)) -eq 0 ]; then
    LON_OFFSET="-$LON_OFFSET"
  fi

  # Apply offsets to coordinates
  local ACTUAL_LAT=$(echo "scale=9; $LAT + $LAT_OFFSET" | bc)
  local ACTUAL_LON=$(echo "scale=9; $LON + $LON_OFFSET" | bc)

  log "Starting route check for $LOCATION_NAME ($LAT, $LON)"
  log "Using coordinates with offset: $ACTUAL_LAT, $ACTUAL_LON (offset: $LAT_OFFSET, $LON_OFFSET)"

  # Get previous state
  PREVIOUS_STATE=$(check_previous_state)
  log "Previous state was: $PREVIOUS_STATE"

  # Send first request to generate routes
  log "Sending route generation request..."

  # Fix for negative coordinates formatting in JSON
  # Ensure negative numbers are properly formatted with leading zero
  local JSON_LON=$ACTUAL_LON
  if [[ $JSON_LON == -* && $JSON_LON != -0* ]]; then
    # Replace "-." with "-0." for proper JSON formatting
    JSON_LON=$(echo $JSON_LON | sed 's/-\./-0\./g')
  fi

  RESPONSE=$(curl -s -X POST "http://$SERVER_IP:7070/api/v1/generateRoutes" \
       -H "Content-Type: application/json" \
       -d "{
           \"start\": {
           \"lat\": $ACTUAL_LAT,
           \"lon\": $JSON_LON
         },
         \"qa\": \"true\",
         \"min_distance\": $MIN_DISTANCE,
         \"max_distance\": $MAX_DISTANCE,
         \"generation_mode\": \"sights\",
         \"generation_params\": {
          \"city_type\": \"outside\",
          \"sights\": \"all\"
        }
       }")

  log "Response: $RESPONSE"

  # Extract UUID from response
  UUID=$(echo $RESPONSE | grep -o '"uuid":"[^"]*' | cut -d'"' -f4)

  if [ -z "$UUID" ]; then
    log "Failed to get UUID from response"
    /home/charm/.local/bin/telegram-send --config $TELEGRAM_CONFIG "BACKEND FAILED: Could not obtain UUID from route generation request for $LOCATION_NAME"
    update_state "FAIL"
    return 1
  fi

  log "Got UUID: $UUID"
  log "Waiting $WAIT_TIME seconds before requesting routes..."
  sleep $WAIT_TIME

  # Send second request to get the routes
  log "Requesting routes with UUID: $UUID"
  ROUTES_RESPONSE=$(curl -s -X GET "http://$SERVER_IP:7070/api/v1/generateRoutes?uuid=$UUID&start_index=0")

  log "Routes response received"

  # Extract route information and status
  if command -v jq >/dev/null 2>&1; then
    # Use jq if available
    ROUTE_COUNT=$(echo "$ROUTES_RESPONSE" | jq '.routes | length')
    TOTAL_ROUTES=$(echo "$ROUTES_RESPONSE" | jq '.totalReturned')
    STATUS=$(echo "$ROUTES_RESPONSE" | jq -r '.status')
  else
    # Fallback to grep and cut if jq is not available
    ROUTE_COUNT=$(echo "$ROUTES_RESPONSE" | grep -o '"routes":\[[^]]*\]' | grep -o "},{" | wc -l)
    ROUTE_COUNT=$((ROUTE_COUNT + 1))
    TOTAL_ROUTES=$(echo "$ROUTES_RESPONSE" | grep -o '"totalReturned":[0-9]*' | cut -d':' -f2)
    STATUS=$(echo "$ROUTES_RESPONSE" | grep -o '"status":"[^"]*' | cut -d'"' -f4)
  fi

  log "Status: $STATUS, Routes in response: $ROUTE_COUNT, Total routes: $TOTAL_ROUTES"

  # Check if we have any routes or if status indicates proper processing
  if [ "$ROUTE_COUNT" -gt 0 ]; then
    log "✅ Success: Response contains routes ($ROUTE_COUNT) for $LOCATION_NAME"

    # Check if previous state was FAIL, then send recovery notification
    if [ "$PREVIOUS_STATE" = "FAIL" ]; then
      log "✅ System recovered after previous failure"
      /home/charm/.local/bin/telegram-send --config $TELEGRAM_CONFIG "✅✅✅ Now it's good. Backend recovered and is generating routes properly for $LOCATION_NAME"
    fi

    update_state "OK"
    return 0
  else
    # No routes and not in a processing state - this indicates a failure
    ERROR_MSG="❌❌❌ BACKEND FAILED: No routes generated for $LOCATION_NAME coordinates $ACTUAL_LAT, $ACTUAL_LON. Status: $STATUS"
    log "$ERROR_MSG"
    /home/charm/.local/bin/telegram-send --config $TELEGRAM_CONFIG "$TELEGRAM_CONFIG $ERROR_MSG"
    update_state "FAIL"
    return 1
  fi
}

#checkLocation 34.686971 33.036906 29 59 "Limassol" 30
#sleep $SLEEP_BETWEEN_TIME
checkLocation 51.50744559999998 -0.1277653 28 59 "London" 90
sleep $SLEEP_BETWEEN_TIME
#checkLocation 59.89686549999996 29.0765628 27 59 "Sbor" 30
#sleep $SLEEP_BETWEEN_TIME
#checkLocation 19.4326296 -99.13317850000001 201 300 "Mexico-City"
#sleep 120

# Generate random coordinates and check a random location
#RANDOM_COORDS=$(generate_random_coordinates)
#RANDOM_LAT=$(echo $RANDOM_COORDS | cut -d' ' -f1)
#RANDOM_LON=$(echo $RANDOM_COORDS | cut -d' ' -f2)
## Random distance range between 30-100km
#MIN_DISTANCE=$((RANDOM % 71 + 30))
#MAX_DISTANCE=$((MIN_DISTANCE + 30))
#checkLocation $RANDOM_LAT $RANDOM_LON $MIN_DISTANCE $MAX_DISTANCE "Random-Location"


#charm@Ubuntu-2404-noble-amd64-base:~/data/AutoRoute/logs$ telegram-send --config group_test.conf "SSSS"
#charm@Ubuntu-2404-noble-amd64-base:~/data/AutoRoute/logs$ telegram-send --config group_prod.conf "SSSS"