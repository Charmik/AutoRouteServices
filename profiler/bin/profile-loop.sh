#!/usr/bin/env bash
#
# Continuous async-profiler loop for the AutoRoute JVM.
# Each minute records ONE JFR with PROFILER_ARGS (default: CPU via ctimer +
# wall-clock) then converts it into one HTML flamegraph per event type into a
# dated tree:
#   data/<DD-Mon>/<HH>/<YYYY-MM-DD_HH-MM-SS>_<event>.html   (e.g. ..._wall.html)
# The JFR is deleted after conversion (HTML is what we keep).
#
# Each capture starts at the top of a minute (H:MM:00); the loop sleeps to the
# next minute boundary before recording. DURATION is < 60 to leave headroom so
# captures never spill into the next minute and skip it.
# Re-resolves the target PID every iteration so it survives app restarts.
#
# NOTE: ctimer is the CPU engine that runs alongside wall; plain `-e cpu` uses
# perf/itimer and can conflict with wall ("Cannot start wall clock with the
# selected event"). For the full event set set PROFILER_ARGS=--all and
# CONVERT_EVENTS="cpu wall alloc lock live nativemem" — but the async-profiler
# docs discourage --all for continuous production profiling.
#
set -uo pipefail

BIN="$(cd "$(dirname "$0")" && pwd)"             # where these scripts live
PROFILER_HOME="${PROFILER_HOME:-$HOME/disk/profiler}"   # where output is written
DATA="$PROFILER_HOME/data"
LOG="$PROFILER_HOME/logs/profile-loop.log"

AP_HOME="${AP_HOME:-$HOME/disk/async-profiler}"
DURATION="${DURATION:-58}"                       # seconds per capture (<60: leaves headroom for minute alignment)
PROFILER_ARGS="${PROFILER_ARGS:--e ctimer --wall 50ms}"   # record CPU (ctimer) + wall-clock together
CONVERT_EVENTS="${CONVERT_EVENTS:-cpu wall}"               # which per-event HTMLs to emit from the JFR
JVM_PATTERN="${JVM_PATTERN:-AutoRoute.jar}"       # pgrep -f pattern for the target

mkdir -p "$DATA" "$PROFILER_HOME/logs"

log() { echo "$(date +%F_%T) $*" >>"$LOG"; }

# Locate the async-profiler binary. Layouts seen in the wild:
#   build/bin/asprof  (source build tree)
#   bin/asprof        (v3.x release tarball)
#   profiler.sh       (v2.x release tarball)
if [ -x "$AP_HOME/build/bin/asprof" ]; then
    PROFILER="$AP_HOME/build/bin/asprof"
elif [ -x "$AP_HOME/bin/asprof" ]; then
    PROFILER="$AP_HOME/bin/asprof"
elif [ -x "$AP_HOME/profiler.sh" ]; then
    PROFILER="$AP_HOME/profiler.sh"
else
    log "FATAL: async-profiler not found under $AP_HOME (looked for build/bin/asprof, bin/asprof, profiler.sh)"
    exit 1
fi

# Locate the JFR -> flamegraph converter (ships next to asprof).
if [ -x "$AP_HOME/build/bin/jfrconv" ]; then
    JFRCONV="$AP_HOME/build/bin/jfrconv"
elif [ -x "$AP_HOME/bin/jfrconv" ]; then
    JFRCONV="$AP_HOME/bin/jfrconv"
else
    log "FATAL: jfrconv not found under $AP_HOME (looked for build/bin/jfrconv, bin/jfrconv)"
    exit 1
fi

log "starting: profiler=$PROFILER args='$PROFILER_ARGS' events='$CONVERT_EVENTS' duration=${DURATION}s pattern='$JVM_PATTERN'"

# On shutdown, stop the in-JVM profiler session so the app isn't left being
# profiled after this service stops/restarts (a killed -d control process
# leaves the session running inside the JVM).
stop_session() { [ -n "${PID:-}" ] && "$PROFILER" stop "$PID" >/dev/null 2>&1; true; }
trap 'log "stopping; clearing JVM profiler session"; stop_session; exit 0' TERM INT

last_cleanup_hour=""

while true; do
    # Hourly retention sweep (cheap; runs once when the hour changes).
    hour_now=$(date +%Y%m%d%H)
    if [ "$hour_now" != "$last_cleanup_hour" ]; then
        PROFILER_HOME="$PROFILER_HOME" "$BIN/cleanup.sh" >>"$LOG" 2>&1 || log "cleanup failed"
        # Bound the log: rotate at ~20MB, keeping one previous file (~40MB max).
        if [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt $((20 * 1024 * 1024)) ]; then
            mv -f "$LOG" "$LOG.1"
            log "rotated log (previous kept at $LOG.1)"
        fi
        last_cleanup_hour="$hour_now"
    fi

    PID=$(pgrep -f "$JVM_PATTERN" | head -n1 || true)
    if [ -z "$PID" ]; then
        log "no JVM matching '$JVM_PATTERN'; retry in 10s"
        sleep 10
        continue
    fi

    # Sleep to the top of the next minute so each capture starts at H:MM:00.
    # (10# forces base-10 so "08"/"09" don't trip the octal parser.)
    wait=$(( (60 - 10#$(date +%S)) % 60 ))
    [ "$wait" -gt 0 ] && sleep "$wait"

    TOP=$(date +%-d-%b)                 # 28-Jun
    HOUR=$(date +%H)                    # 14
    TS=$(date +%Y-%m-%d_%H-%M-%S)       # 2026-06-28_14-23-00
    OUTDIR="$DATA/$TOP/$HOUR"
    JFR="$PROFILER_HOME/.inflight.jfr"
    mkdir -p "$PROFILER_HOME"

    # Clear any session left running in the JVM by a previously-interrupted
    # capture; otherwise the next start fails with "Profiler already started".
    # No-op (and harmless error) if nothing is active.
    "$PROFILER" stop "$PID" >/dev/null 2>&1 || true

    # Record one multi-event JFR, then split it into per-event HTML flamegraphs.
    # The dated dir is (re)created right before the HTMLs land, so a directory
    # removed mid-capture doesn't cost us the recording.
    if "$PROFILER" $PROFILER_ARGS -d "$DURATION" -f "$JFR" "$PID" >>"$LOG" 2>&1; then
        mkdir -p "$OUTDIR"
        for ev in $CONVERT_EVENTS; do
            # A given event may have no samples this minute; tolerate per-event failure.
            "$JFRCONV" --"$ev" "$JFR" "$OUTDIR/${TS}_${ev}.html" >>"$LOG" 2>&1 \
                || log "jfrconv --$ev produced nothing for $TS (no samples?)"
        done
        rm -f "$JFR"
    else
        log "profiler failed for PID $PID; retry in 5s"
        rm -f "$JFR"
        sleep 5
    fi
done
