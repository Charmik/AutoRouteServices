# Continuous profiler for AutoRoute

Every minute records one JFR — CPU (`ctimer`) **and** wall-clock together —
from the live `AutoRoute.jar` JVM with [async-profiler], then splits it into a
`_cpu.html` and a `_wall.html` flamegraph in a dated tree, and serves them over
HTTP with basic auth. The JFR is deleted after conversion.

Code and output are split across two locations:

```
~/data/AutoRouteServices/profiler/      # CODE (rsynced from the repo)
├── bin/{profile-loop.sh, cleanup.sh, auth_server.py}
└── systemd/{continuous-profiler.service, profiler-web.service}

~/disk/profiler/                        # OUTPUT (big disk, PROFILER_HOME)
├── data/<DD-Mon>/<HH>/<YYYY-MM-DD_HH-MM-SS>_<event>.html   # _cpu, _wall
├── logs/profile-loop.log
└── web.env            # PROFILER_USER / PROFILER_PASS  (you create this, NOT rsynced)
```

The scripts run in place from `~/data/...`; the `PROFILER_HOME` env var (set in
the systemd unit, default `~/disk/profiler`) decides where profiles and logs are
written — so output never lands back in the rsynced repo tree.

- **Mode:** CPU (`ctimer`) + wall-clock, 58s capture aligned to `H:MM:00`,
  **2 HTMLs per minute** (~2880 files/day).
- **Retention:** files older than 14 days deleted (hourly sweep). Change with
  `RETENTION_DAYS` in `cleanup.sh` / the service env.
- **No root needed:** `ctimer`/wall sample via per-thread timers, async-profiler
  attaches to a same-uid JVM. Runs as `charm`.

> Want the full picture for a window? Set `PROFILER_ARGS=--all` and
> `CONVERT_EVENTS="cpu wall alloc lock live nativemem"` to also get
> alloc/lock/live/nativemem — but the async-profiler docs **discourage `--all`
> for continuous production profiling** (extra overhead), so keep an eye on
> AutoRoute latency if you do.

## Install on hz4

After you've rsynced `AutoRouteServices` to `~/data` (so the code is at
`~/data/AutoRouteServices/profiler/`), run the installer on hz4:

```bash
cd ~/data/AutoRouteServices/profiler
./install.sh
```

`install.sh` is idempotent — it chmods the scripts, creates
`~/disk/profiler/web.env` (only if missing, so it never clobbers your
password), copies the systemd units, enables + restarts both services, and
wires nginx to serve the flamegraphs under `/profiler/` (copies the snippet to
`/etc/nginx/snippets/` and adds an `include` to the site's `server{}` block,
only if not already there, then `nginx -t` + reload). Then verify:

```bash
systemctl status continuous-profiler.service profiler-web.service
tail -f ~/disk/profiler/logs/profile-loop.log
```

> Change the password: edit `~/disk/profiler/web.env`, then
> `sudo systemctl restart profiler-web.service`.

**On later redeploys** you only re-run the rsync; the running services keep
using the updated scripts on their next loop iteration. If you changed a
`.service` file, also re-copy it and `sudo systemctl daemon-reload &&
sudo systemctl restart continuous-profiler.service profiler-web.service`.

Browse at **`http://88.99.161.250/profiler/`** (nginx → localhost:8400, basic
auth `charm`). The `:8400` service itself stays bound to localhost. If
`install.sh` couldn't auto-detect your site config, re-run it with
`NGINX_SITE=/etc/nginx/sites-enabled/<yoursite> ./install.sh`.

## Tuning

Override via `Environment=` lines in `continuous-profiler.service`:

| Var | Default | Meaning |
|-----|---------|---------|
| `DURATION` | `58` | seconds per capture (<60 so captures stay minute-aligned) |
| `PROFILER_ARGS` | `-e ctimer --wall 50ms` | what asprof records into the JFR |
| `CONVERT_EVENTS` | `cpu wall` | which per-event HTMLs to emit from the JFR |
| `JVM_PATTERN` | `AutoRoute.jar` | `pgrep -f` pattern for the target JVM |
| `AP_HOME` | `~/disk/async-profiler` | async-profiler install dir (needs `asprof` + `jfrconv`) |

`CONVERT_EVENTS` should be a subset of what `PROFILER_ARGS` actually records;
events with no samples in a given minute still produce a (near-empty) HTML.

Sharper line attribution (optional) — add to the **app's** JVM flags, not here:
`-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints`.

[async-profiler]: https://github.com/async-profiler/async-profiler
