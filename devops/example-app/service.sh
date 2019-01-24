#!/bin/sh
cd /www
cp /www/nginx.conf /etc/nginx/nginx.conf
nginx -c nginx.conf 
# spawn the fcgi app on port 8000 with no fork
spawn-fcgi -p 8000 -n ./cgi_program

