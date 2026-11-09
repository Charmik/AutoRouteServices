#!/bin/bash
set -e

# Debug-only OSRM service for the WALK graph (osrm-backend HTTP + osrm-frontend), sibling of
# start_service_osrm.sh (road). Runs ALONGSIDE the road service on different ports so both can be
# open at once:
#   road   : backend :8003  frontend http://localhost:9966  (start_service_osrm.sh)
#   gravel : backend :8004  frontend http://localhost:9967  (start_service_osrm_gravel.sh)
#   walk   : backend :8007  frontend http://localhost:9968  (this script)
# NOTE: in dev/test/prod the app routes via the OsrmLib JNI library — this HTTP service is for
# eyeballing walk routes / inspecting speeds in osrm-frontend debug mode ONLY.

PORT=8007
FRONTEND_PORT=9968
# Inside an AutoRoute worktree with its own graphs (worktree.env exports AUTOROUTE_WORKTREE_OSRM=1) serve those;
# otherwise the fixed main graph, exactly as before.
if [ "$AUTOROUTE_WORKTREE_OSRM" = "1" ]; then
  OSRM_DATA_DIR="${OSRM_WALK_DATA_DIR:?OSRM_WALK_DATA_DIR must be set for a worktree with its own graphs}"
else
  OSRM_DATA_DIR="$HOME/data/osrm_walk"
fi
OSRM_BINARY="$HOME/data/osrm-backend/build/osrm-routed"
LOG_FILE="$OSRM_DATA_DIR/osrm.log"
FRONTEND_NAME="osrm-frontend-walk"

# --- backend: kill existing osrm-routed on the walk port (leaves road/gravel alone) ---
EXISTING_PID=$(lsof -ti tcp:$PORT 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  echo "Killing existing process on port $PORT (PID: $EXISTING_PID)"
  kill $EXISTING_PID 2>/dev/null || true
  sleep 1
  if kill -0 $EXISTING_PID 2>/dev/null; then
    kill -9 $EXISTING_PID 2>/dev/null || true
  fi
fi

[ -f "$OSRM_DATA_DIR/merged.osrm.mldgr" ] || { echo "no walk graph at $OSRM_DATA_DIR - run mmbw first"; exit 1; }
echo "Starting WALK OSRM backend on port $PORT (log: $LOG_FILE)"
nohup "$OSRM_BINARY" --algorithm mld --mmap on "$OSRM_DATA_DIR/merged.osrm" -p $PORT > "$LOG_FILE" 2>&1 &
NEW_PID=$!

# Wait for ready (Limassol probe; the local walk graph covers cyprus+england)
for i in $(seq 1 15); do
  if curl -s "http://localhost:$PORT/route/v1/foot/33.040,34.669;33.050,34.675" > /dev/null 2>&1; then
    echo "WALK OSRM backend ready on port $PORT (PID: $NEW_PID)"
    break
  fi
  sleep 1
done

# --- frontend: recreate the walk osrm-frontend container (leaves the others alone) ---
if command -v docker >/dev/null 2>&1; then
  echo "Restarting walk frontend container '$FRONTEND_NAME' on http://localhost:$FRONTEND_PORT"
  docker stop "$FRONTEND_NAME" 2>/dev/null || true
  docker rm "$FRONTEND_NAME" 2>/dev/null || true
  docker run -d --name "$FRONTEND_NAME" \
    -p $FRONTEND_PORT:9966 \
    -e OSRM_BACKEND="http://localhost:$PORT" \
    -e OSRM_CENTER="34.6750,33.0450" \
    -e OSRM_ZOOM="14" \
    -e OSRM_LABEL="Walk" \
    -e OSRM_LANGUAGE="en" \
    osrm/osrm-frontend >/dev/null \
    && echo "Walk frontend up: http://localhost:$FRONTEND_PORT" \
    || echo "WARNING: walk frontend container failed to start"
else
  echo "docker not found — backend only; point any osrm-frontend at http://localhost:$PORT"
fi
