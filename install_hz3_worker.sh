#!/usr/bin/env bash
# Sets up the hz3 worker. Run on hz3 as charm: AutoRouteServices/install_hz3_worker.sh
# Installs autoroute-hz3.service and the CI freeze scripts in hz3-worker/, both next to this script.
# Idempotent. Doesn't start the service: the first prod deploy to hz3 brings the jar + app.properties, then
#   systemctl --user enable --now autoroute.service
# Needs once, with sudo (prints what's missing):
#   sudo loginctl enable-linger charm                      user services run without a login
#   sudo systemctl set-property user.slice CPUWeight=1 IOWeight=1
#   sudo systemctl restart ar-actions-runner actions-runner   (only while no CI job runs: picks up the hooks)
set -euo pipefail
unit="$(cd "$(dirname "$0")" && pwd)/autoroute-hz3.service"
here="$(cd "$(dirname "$0")" && pwd)/hz3-worker"
hooks=/home/charm/disk/autoroute-worker
mkdir -p "$hooks" /home/charm/disk/tmp /home/charm/disk/heapdumps \
    /home/charm/disk/osm /home/charm/disk/models /home/charm/data/AutoRoute/logs "$hooks/elevation"

install -m 755 "$here/ci-worker.sh" "$hooks/ci-worker.sh"
rm -rf /home/charm/disk/ci-active   # old flag dir (CiPause), the flags live in /dev/shm/ci-active now

# one flag name per runner: the hook copies live in each runner's own directory
for runner in ar-actions-runner actions-runner; do
    dir=/home/charm/disk/$runner
    [ -d "$dir" ] || { echo "no $dir, skipped"; continue; }
    install -m 755 "$here/ci-job-started.sh" "$dir/ci-job-started.sh"
    install -m 755 "$here/ci-job-completed.sh" "$dir/ci-job-completed.sh"
    touch "$dir/.env"
    sed -i '/^ACTIONS_RUNNER_HOOK_JOB_\(STARTED\|COMPLETED\)=/d' "$dir/.env"
    echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=$dir/ci-job-started.sh" >> "$dir/.env"
    echo "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$dir/ci-job-completed.sh" >> "$dir/.env"
    echo "hooks set in $dir/.env"
done

# the elevation service refuses to start without a GeoTIFF; nothing here computes elevation
if ! ls "$hooks/elevation"/*.tif >/dev/null 2>&1; then
    tif=$(ls /home/charm/disk/AutoRoute/src/test/resources/elevation_data/*.tif 2>/dev/null | head -1 || true)
    [ -n "$tif" ] && cp "$tif" "$hooks/elevation/" || echo "WARN: put one .tif into $hooks/elevation"
fi

mkdir -p /home/charm/.config/systemd/user
install -m 644 "$unit" /home/charm/.config/systemd/user/autoroute.service
for u in ci-worker-sync.service ci-worker-sync.timer; do
    install -m 644 "$here/$u" "/home/charm/.config/systemd/user/$u"
done
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if systemctl --user daemon-reload; then
    systemctl --user enable --now ci-worker-sync.timer
    echo "user units installed, ci-worker-sync.timer running"
else
    echo "WARN: no user manager (linger off?)"
fi

[ "$(loginctl show-user charm -p Linger --value)" = yes ] || echo "TODO (sudo): loginctl enable-linger charm"
[ "$(cat /sys/fs/cgroup/user.slice/cpu.weight)" = 1 ] || echo "TODO (sudo): systemctl set-property user.slice CPUWeight=1 IOWeight=1"
echo "TODO (sudo, while CI is idle): systemctl restart ar-actions-runner actions-runner"
