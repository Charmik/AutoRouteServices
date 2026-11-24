#!/usr/bin/env bash
# GitHub runner hook on hz3 (ACTIONS_RUNNER_HOOK_JOB_COMPLETED): the job ended; the worker is thawed once no
# other runner's flag is left (ci-worker.sh). Never fails the job.
dir=/dev/shm/ci-active
name="$(basename "$(dirname "$(readlink -f "$0")")")"   # the runner directory holding this copy
rm -f "$dir/$name" || echo "ci-job-completed: couldn't remove $dir/$name" >&2
/home/charm/disk/autoroute-worker/ci-worker.sh sync
exit 0
