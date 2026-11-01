#!/usr/bin/env bash
# Loads part1/part2 into OSRM shared memory.
# Old segments are removed first and the load is refused if they are not really gone:
# ipcrm/--spring-clean only MARK a segment, its RAM stays until the last process detaches,
# and osrm-datastore allocates the new region before freeing the old one -> two copies -> OOM.
set -euo pipefail

OSRM_BUILD=~/disk/osrm-backend/build
NEED_GB=${NEED_GB:-220}   # part1 ~150GiB + part2 ~64GiB (measured 213GiB) + margin

cd "$OSRM_BUILD"

if pgrep -x osrm-datastore >/dev/null || pgrep -x osrm-routed >/dev/null; then
  echo "osrm-datastore/osrm-routed is running, stop it first:"; pgrep -a 'osrm-(datastore|routed)'; exit 1
fi

# Remove every segment of this user directly (--spring-clean silently aborts unless you type 'Y')
for id in $(ipcs -m | awk -v u="$USER" '$3==u {print $2}'); do ipcrm -m "$id"; done
./osrm-datastore --remove-locks

if [ -n "$(ipcs -m | awk -v u="$USER" '$3==u')" ]; then
  echo "Old shared memory is still held (status 'dest' = attached by the process in lpid/cpid):"
  ipcs -m; ipcs -m -p; exit 1
fi

avail_gb=$(awk '/MemAvailable/ {print int($2/1048576)}' /proc/meminfo)
if [ "$avail_gb" -lt "$NEED_GB" ]; then
  echo "Only ${avail_gb}GiB available, need ${NEED_GB}GiB (override with NEED_GB=...)"; free -h; exit 1
fi

./osrm-datastore --dataset-name=part1 /home/charm/data/osrm/part1/planet-part1-modified
./osrm-datastore --dataset-name=part2 /home/charm/data/osrm/part2/planet-part2-modified
./osrm-datastore --list
ipcs -m
free -h

# Debug only (never used by the app):
#./osrm-routed --algorithm ch --shared-memory on --dataset-name part1
#./osrm-routed --algorithm ch --shared-memory on --dataset-name part2


# check shared-memory files
#JAVA_PID=$(pgrep -f "AutoRoute.jar" | head -1)
#cat /proc/$JAVA_PID/maps | grep -i "shmem\|osrm"
