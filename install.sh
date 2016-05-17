#!/usr/bin/env bash

echo -n "Ingrese el # de condominio: "
read condominio

aptitude update

aptitude install -y nginx-extras python-pip redis-server python-redis gcc supervisor python-dev lsof tcpdump

pip install -U Celery[redis]

mkdir /opt/doors

cat >/opt/doors/tasks.py << EOL
from celery import Celery
import time
import os


app = Celery('TocSEC', broker='redis://localhost/0')

if os.environ.get('DONT_GPIO', None) is None:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BOARD)
    GPIO.setup(16, GPIO.OUT)
    GPIO.setup(18, GPIO.OUT)

@app.task
def open_door(door):
    GPIO.output(door, 1)
    time.sleep(2)
    GPIO.output(door, 0)
    time.sleep(2)
EOL

cat > /opt/doors/open_door.py << EOL
import os
import sys

os.environ['DONT_GPIO'] = 'true'

from tasks import open_door

var = sys.argv[1].strip()

if var == "1":
    open_door.delay(16)
elif var == "2":
    open_door.delay(18)
else:
    sys.exit(42)
EOL


cat  >/etc/supervisor/conf.d/app-task.conf << EOL
[program:appq_tasks]
command=/usr/local/bin/celery -A tasks worker -c 2
directory=/opt/doors/
autostart=true
autorestart=true
environment=C_FORCE_ROOT=1
stderr_logfile=/dev/null
stdout_logfile=/dev/null

EOL

cat >/etc/rc.local << EOL

#!/bin/sh -e
#
# rc.local
#

# Print the IP address
_IP=$(hostname -I) || true
if [ "$_IP" ]; then
  printf "Mi direccion IP es %s\n" "$_IP"
fi

exit 0

EOL

cat >/etc/cron.d/actualizaIP << EOL
#ejecuta actualizacion de ip
*/10 * * * * root curl http://tocseg.cl/in/actualizarIP.php?c=$condominio
EOL


cat > /etc/nginx/nginx.conf << EOL

user www-data;
worker_processes 1;
pid /run/nginx.pid;

events {
        worker_connections 1024;
        multi_accept on;
        use epoll;
}

http {

    limit_req_zone \$binary_remote_addr zone=extreme:10m rate=8r/s;

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;


	include /etc/nginx/mime.types;
	default_type application/octet-stream;


	ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
	ssl_prefer_server_ciphers on;


	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;


	gzip on;
	gzip_disable "msie6";


	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}


EOL

cat > /etc/nginx/sites-enabled/default << EOL
server {
	listen 80 default_server;
	listen 8080 default_server;
	listen 5000 default_server;

	root /usr/share/nginx/html;
	index index.html index.htm;

	server_name localhost;

	location / {
		try_files \$uri \$uri/ =404;
	}

    location ~ ^/api/v1.0/abreBarrera/(.*)$ {
        limit_req zone=extreme burst=8;
        default_type 'text/plain';
        set \$call_of_action \$1;
        content_by_lua '
            local call_of_action =  ngx.var.call_of_action
            local outcode = os.execute("python /opt/doors/open_door.py " .. call_of_action)
            ngx.say(call_of_action, ":", outcode)
        ';
    }
}
EOL


service supervisor restart
service nginx restart

update-rc.d redis-server defaults
update-rc.d supervisor defaults
update-rc.d nginx defaults
