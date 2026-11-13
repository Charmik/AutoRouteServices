#!/usr/bin/env bash
#
# First-time install of the continuous profiler on hz4.
# Run after rsyncing AutoRouteServices to ~/data:
#     cd ~/data/AutoRouteServices/profiler && ./install.sh
#
# Idempotent: safe to re-run. Re-copies units and restarts the services.
# Does NOT overwrite an existing ~/disk/profiler/web.env (your password).
#
set -euo pipefail

cd "$(dirname "$0")"

# 1. Make scripts executable (rsync may not preserve the +x bit)
chmod +x bin/*.sh bin/auth_server.py

# 2. Web credentials on the big disk (created once; never clobbered on re-run)
mkdir -p ~/disk/profiler
if [ ! -f ~/disk/profiler/web.env ]; then
    printf 'PROFILER_USER=charm\nPROFILER_PASS=charmik\n' > ~/disk/profiler/web.env
    chmod 600 ~/disk/profiler/web.env
    echo "created ~/disk/profiler/web.env (user=charm pass=charmik — change PROFILER_PASS!)"
else
    echo "~/disk/profiler/web.env already exists; leaving it untouched"
fi

# 3. Install + (re)start the two services
sudo cp systemd/continuous-profiler.service systemd/profiler-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now continuous-profiler.service profiler-web.service
sudo systemctl restart continuous-profiler.service profiler-web.service

# 4. nginx: expose under http://<host>/profiler/ (idempotent)
if command -v nginx >/dev/null 2>&1; then
    SNIPPET=/etc/nginx/snippets/routecycle-profiler.conf
    sudo install -D -m 644 nginx-profiler.conf "$SNIPPET"

    # Find the site config to add the include to (override with NGINX_SITE=...).
    SITE="${NGINX_SITE:-}"
    if [ -z "$SITE" ]; then
        for c in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
            [ -f "$c" ] || continue
            if sudo grep -qE '^[[:space:]]*(server[[:space:]]*\{|listen)' "$c"; then
                SITE="$c"; break
            fi
        done
    fi

    if [ -z "$SITE" ] || [ ! -f "$SITE" ]; then
        echo "nginx: no site config found. Add 'include $SNIPPET;' to your server{} block, or re-run with NGINX_SITE=/path/to/site"
    elif sudo grep -Fq "$SNIPPET" "$SITE"; then
        echo "nginx: include already present in $SITE — nothing to do"
    else
        # Insert the include right after the first `listen` line (inside a server{}).
        INCLUDE_LINE="    include $SNIPPET;  # routecycle-profiler"
        sudo sed -i "0,/^[[:space:]]*listen[^;]*;/s||&\n${INCLUDE_LINE}|" "$SITE"
        echo "nginx: added include to $SITE"
    fi

    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo "nginx: reloaded"
    else
        echo "nginx: config test FAILED — not reloaded. Review $SITE"
    fi
else
    echo "nginx not installed; skipping /profiler/ setup (reach it directly on :8400)"
fi

# 5. Show status
systemctl --no-pager status continuous-profiler.service profiler-web.service || true

echo
echo "Done. Logs: tail -f ~/disk/profiler/logs/profile-loop.log"
echo "      Web:  http://88.99.161.250/profiler/   (user charm)"
