#!/usr/bin/env bash
#
# Delete flamegraphs older than RETENTION_DAYS and prune the empty dirs.
#
set -uo pipefail

PROFILER_HOME="${PROFILER_HOME:-$HOME/disk/profiler}"
DATA="$PROFILER_HOME/data"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

[ -d "$DATA" ] || exit 0

find "$DATA" -type f -name '*.html' -mtime "+$RETENTION_DAYS" -delete
find "$DATA" -mindepth 1 -type d -empty -delete

echo "$(date +%F_%T) cleanup done (retention ${RETENTION_DAYS}d)"
