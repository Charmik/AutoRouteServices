#!/bin/bash

# Log file setup
#LOG_DIR="/home/charm/data/backed_health_logs"
LOG_DIR="."
LOG_FILE="$LOG_DIR/route-check-$(date +%Y%m%d).log"
STATE_FILE="$LOG_DIR/route-check-state.txt"

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

# Function to check a location
checkLocation() {
  local LAT=$1
  local LON=$2
  local MIN_DISTANCE=$3
  local MAX_DISTANCE=$4
  local LOCATION_NAME=${5:-"unnamed location"}  # Optional name parameter

  log "Starting route check for $LOCATION_NAME ($LAT, $LON)"

  # Get previous state
  PREVIOUS_STATE=$(check_previous_state)
  log "Previous state was: $PREVIOUS_STATE"

  log "Using coordinates: $LAT, $LON"

  # Send first request to generate routes
  log "Sending route generation request..."
  RESPONSE=$(curl -s -X POST "http://65.21.97.107:7070/api/v1/generateRoutes" \
       -H "Content-Type: application/json" \
       -d "{
         \"lat\": $LAT,
         \"lon\": $LON,
         \"min_distance\": $MIN_DISTANCE,
         \"max_distance\": $MAX_DISTANCE,
         \"generation_mode\": \"sights\",
         \"generation_params\": {}
       }")

  log "Response: $RESPONSE"

  # Extract UUID from response
  UUID=$(echo $RESPONSE | grep -o '"uuid":"[^"]*' | cut -d'"' -f4)

  if [ -z "$UUID" ]; then
    log "Failed to get UUID from response"
    /home/charm/.local/bin/telegram-send "BACKEND FAILED: Could not obtain UUID from route generation request for $LOCATION_NAME"
    update_state "FAIL"
    return 1
  fi

  log "Got UUID: $UUID"
  log "Waiting 10 seconds before requesting routes..."
  sleep 10

  # Send second request to get the routes
  log "Requesting routes with UUID: $UUID"
  ROUTES_RESPONSE=$(curl -s -X GET "http://65.21.97.107:7070/api/v1/generateRoutes?uuid=$UUID&start_index=0")

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
      /home/charm/.local/bin/telegram-send "✅✅✅ Now it's good. Backend recovered and is generating routes properly for $LOCATION_NAME"
    fi

    update_state "OK"
    return 0
  else
    # No routes and not in a processing state - this indicates a failure
    ERROR_MSG="❌❌❌ BACKEND FAILED: No routes generated for $LOCATION_NAME coordinates $LAT, $LON. Status: $STATUS"
    log "$ERROR_MSG"
    /home/charm/.local/bin/telegram-send "$ERROR_MSG"
    update_state "FAIL"
    return 1
  fi
}

# Function to generate a small random offset
add_random_offset() {
  local BASE_COORD=$1
  local OFFSET=$(echo "scale=6; $RANDOM / 10000000" | bc)
  echo "scale=6; $BASE_COORD + $OFFSET" | bc
}

checkLocation 34.686971 33.036906 29 59 "Limassol"
sleep 120
checkLocation 51.50744559999998 -0.1277653 28 59 "London"
sleep 120
checkLocation 59.89686549999996 29.0765628 27 59 "Sbor"
sleep 120
checkLocation 19.4326296 -99.13317850000001 200 300 "Mexico-City"