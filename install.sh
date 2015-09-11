#!/usr/bin/env bash

echo -n "ingrese el # de condominio: "
read condominio

aptitude update

aptitude install -y python-pip redis-server python-redis gcc supervisor python-dev python-lxml lsof tcpdump

pip install -U Celery Flask flask-spyne


mkdir /opt/doors

cat >/opt/doors/tasks.py << EOL
from celery import Celery
import time
import os


app = Celery('hello', broker='redis://localhost/0')

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


cat > /opt/doors/ws.py  << EOL 

from flask import Flask
from flask.ext.spyne import Spyne
from spyne.protocol.soap import Soap11
from spyne.model.primitive import Unicode, Integer
from spyne.model.complex import Iterable

import os

os.environ['DONT_GPIO'] = 'true'

from tasks import open_door

app = Flask(__name__)
spyne = Spyne(app)

class recibeWs(spyne.Service):
    __service_url_path__ = '/tarjeta/recibeWs.php'
    __in_protocol__ = Soap11(validator='lxml')
    __out_protocol__ = Soap11()

    @spyne.srpc(Integer, _returns=Integer)
    def abreBarrera(var):
        if var == 1:
            open_door.delay(16)
        elif var==2:
            open_door.delay(18)
        return var

@app.route('/api/v1.0/abreBarrera/<int:var>')
def abreBarrera(var):
    if var == 1:
        open_door.delay(16)
    elif var==2:
        open_door.delay(18)
    return str(var)

if __name__ == '__main__':
    app.run(host = '0.0.0.0')



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

[program:appq_api]
command=python ws.py
directory=/opt/doors/
autostart=true
autorestart=true
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
  printf "My IP address is %s\n" "$_IP"
fi

exit 0

EOL



cat >/etc/cron.d/actualizaIP << EOL

#ehecuta actualizacion de ip

*/10 * * * * root curl http://tocseg.cl/in/actualizarIP.php?c=$condominio

EOL


service supervisor restart

update-rc.d redis-server defaults
update-rc.d supervisor defaults

