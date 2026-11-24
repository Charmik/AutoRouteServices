#!/usr/bin/env bash
# GitHub runner hook on hz3 (ACTIONS_RUNNER_HOOK_JOB_STARTED in the runner's .env): a CI job starts, so the
# hz3 worker is frozen (ci-worker.sh). One flag per runner: both runners can run jobs. Never fails the job.
dir=/dev/shm/ci-active
name="$(basename "$(dirname "$(readlink -f "$0")")")"   # the runner directory holding this copy
mkdir -p "$dir" && touch "$dir/$name" || echo "ci-job-started: couldn't write $dir/$name" >&2
/home/charm/disk/autoroute-worker/ci-worker.sh sync
exit 0
