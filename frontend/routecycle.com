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

    # Proxy API requests to the backend server over HTTP
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