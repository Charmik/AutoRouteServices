#nging config for https://routecycle.com production
#file is located here: /etc/nginx/sites-available/routecycle.com
#to connect to server: ssh root@$do_virt

server {
    server_name routecycle.com www.routecycle.com;

    #root /home/charm/routeplanner/dist;
    root /home/panda/routeplanner/www;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Gravel generation goes to the gravel-only backend (hz1), which holds the gravel OSRM
    # graphs. The frontend sends gravel requests (and every poll/edit for a gravel route) to
    # /api/gravel/v1/...; strip the /gravel segment so hz1 sees the same /api/v1/... paths.
    # Longer prefix than /api/v1 and /api, so nginx picks this for gravel URLs.
    location /api/gravel/v1 {
        proxy_pass http://144.76.198.221:7070/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # Road generation goes to the road backend (hz4). Symmetric with the gravel prefix; strip the
    # /road segment so hz4 sees the same /api/v1/... paths. The web app targets this path.
    location /api/road/v1 {
        proxy_pass http://65.21.136.166:7070/api/v1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass_request_headers on;
    }

    # LEGACY, backward-compatibility only: the un-prefixed road path. Kept so already-shipped clients
    # (the iOS app, browser tabs holding an older build) keep working after the web app moved to
    # /api/road/v1.
    # TODO: drop this /api/v1 block once every client (web + iOS) targets /api/road/v1.
    location /api/v1 {
        proxy_pass http://65.21.136.166:7070/api/v1;
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