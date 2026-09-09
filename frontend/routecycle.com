#nging config for https://routecycle.com production
#file is located here: /etc/nginx/sites-available/routecycle.com
#to connect to server: ssh root@$do_virt

# Where each class of API traffic goes. These four names are the only place a backend host appears,
# so moving a class of traffic to another server is a one-line edit plus
# `nginx -t && systemctl reload nginx` -- no frontend rebuild, because the browser only ever sees
# the public /api/... prefixes.
#
# hz4 = 65.21.136.166, hz5 = 176.9.23.116, hz1 = 144.76.198.221 (see docs/ARCHITECTURE.md).

# User-scoped API: independent of any routing profile -- favorites, recent, sights, user settings,
# feedback, location, street view, Garmin. Legacy un-prefixed clients (the iOS app and cached web
# builds) also GENERATE routes through /api/v1, so this must stay on the road server until those
# clients are gone.
upstream routecycle_api    { server 65.21.136.166:7070; }

# All Strava paths. To move Strava to hz5, the ONLY nginx edit needed is the `server` address in the
# `upstream routecycle_strava { ... }` line at the end of THIS comment block -- change
# `server 65.21.136.166:7070;` to `server 176.9.23.116:7070;`, then `nginx -t && systemctl reload
# nginx`. No other block, and no frontend rebuild: the browser only ever sees the public /api paths.
# Covers /api/v1/strava/* (webhook, fitness, routes, sync/status), /api/v1/auth/strava/* (callback,
# session, logout, disconnect) and /api/v1/activities, which is entirely Strava-backed.
#
# hz5 is ALREADY serving this API: app-prod-hz5.properties sets javalin.enabled=true, and
# hz5:7070/api/v1/location answers 200 today, so no deploy is needed to make the flip work.
# hz5 also has routing.service=STUB, which is exactly why STRAVA is safe to move there and the
# other prefixes are not: nothing under /api/v1/strava, /api/v1/auth/strava or /api/v1/activities
# needs an OSRM graph, while generation does.
#
# BEFORE changing that address, note two things that do NOT follow the prefix on their own:
#  1. `strava.webhook.create.subscription=true` is set only in app-prod-hz4.properties; it must move
#     with /api/v1/strava/webhook or nobody owns the Strava subscription.
#
# Deliberately NOT in this group, left on routecycle_api:
# /api/v1/user/settings/updateStravaDescription, /api/v1/user/settings/stravaDescriptionDetails and
# /api/v1/routes/claim -- Strava-adjacent, but they belong to user settings / route ownership.
# Move them too if Strava's database access moves.
upstream routecycle_strava { server 176.9.23.116:7070; }

# Road route generation and every uuid-scoped route edit -- must be the box holding the road OSRM
# graph, because the in-memory generation state for a uuid lives only there.
upstream routecycle_road   { server 65.21.136.166:7070; }

# Gravel generation -- the box holding the gravel OSRM graph (hz1). NOT LIVE YET, so every
# /api/gravel/v1 request currently returns nginx 502. That is expected and is the correct signal:
# before this block existed the same request fell through to `location /api` and got Photon's 404,
# which looked like an application bug instead of an undeployed backend.
upstream routecycle_gravel { server 144.76.198.221:7070; }

server {
    server_name routecycle.com www.routecycle.com;

    #root /home/charm/routeplanner/dist;
    root /home/panda/routeplanner/www;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Strava, carved out of /api/v1 so it can be re-pointed on its own. nginx picks the LONGEST
    # matching prefix, so these three win over /api/v1 below regardless of order in this file.
    location /api/v1/strava {
        proxy_pass http://routecycle_strava/api/v1/strava;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    location /api/v1/auth/strava {
        proxy_pass http://routecycle_strava/api/v1/auth/strava;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    location /api/v1/activities {
        proxy_pass http://routecycle_strava/api/v1/activities;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # Road generation. The trailing /api/v1 replaces the matched /api/road/v1 prefix, so the backend
    # -- which registers only /api/v1/* -- sees the path it expects.
    location /api/road/v1 {
        proxy_pass http://routecycle_road/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # Gravel is served by hz1, which runs the same JAR and so registers the same /api/v1 paths.
    location /api/gravel/v1 {
        proxy_pass http://routecycle_gravel/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # The profile-neutral API: everything user-scoped, plus legacy un-prefixed clients.
    # NOT legacy and NOT safe to delete -- the web app's VITE_BACKEND_API_URL points here, so
    # removing this block takes Strava login, favorites and activities down with it.
    location /api/v1 {
        proxy_pass http://routecycle_api/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    location /reverse {
        proxy_pass http://176.9.23.116:2322/reverse;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # Photon geocoder, and the CATCH-ALL for /api: any /api/... prefix not declared above lands here
    # and gets Photon's own Javalin 404, which reads like an AutoRoute bug but is not. That is
    # exactly how the Sep 8 2026 outage presented -- the deployed web build asked for
    # /api/road/v1/... before this file had that block.
    location /api {
        proxy_pass http://176.9.23.116:2322/api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }



    # Optional: serve static files with caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 365d;
    }


    listen 443 ssl http2; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/routecycle.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/routecycle.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    listen 80 default_server;
    server_name routecycle.com www.routecycle.com;
    return 301 https://$server_name$request_uri;
}
