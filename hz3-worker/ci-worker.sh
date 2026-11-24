#!/usr/bin/env bash
# hz3: freezes the heavy-task worker (user unit autoroute.service) while CI runs and thaws it when CI is idle.
#   ci-worker.sh sync      freeze if any CI flag exists, thaw if none; idempotent
# Called by the runner job hooks (ci-job-*.sh), by use-hz3 jobs and every minute by ci-worker-sync.timer, which
# also repairs a missed hook or a worker restarted mid-job. A flag is a file in /dev/shm/ci-active (gone after a
# reboot); one older than 12 h (longer than any CI job) was left by a runner that died mid-job and is ignored.
# Freezing (cgroup freezer) stops the JVM where it is; its memory stays in RAM (62 GB fit the worker + CI; under
# real pressure the kernel may still swap some of it). osmium runs in its own scopes (OsmiumMemoryCap), so a running osmium isn't frozen and finishes. DB
# writes are autocommit: a frozen JVM holds no locks on the prod DB. CPU/IO: user.slice has weight 1. Never fails.
set -u
flags=/dev/shm/ci-active
unit=autoroute.service
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

log() {
    echo "ci-worker: $*"
    logger -t ci-worker "$*" 2>/dev/null || true
}

ci_running() {
    [ -d "$flags" ] && [ -n "$(find "$flags" -type f -mmin -720 -print -quit 2>/dev/null)" ]
}

[ "${1:-}" = sync ] || { echo "usage: $0 sync" >&2; exit 0; }
exec 9>/dev/shm/ci-worker.lock
flock 9
systemctl --user -q is-active "$unit" || exit 0
state=$(systemctl --user show -p FreezerState --value "$unit")
if ci_running; then
    [ "$state" = running ] || exit 0
    if ! systemctl --user freeze "$unit"; then
        log "couldn't freeze $unit"
        exit 0
    fi
    log "CI runs: $unit frozen"
else
    [ "$state" = running ] && exit 0
    if systemctl --user thaw "$unit"; then
        log "CI idle: $unit thawed"
    else
        log "couldn't thaw $unit"
    fi
fi
exit 0
