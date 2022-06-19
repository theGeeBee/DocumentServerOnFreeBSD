#!/bin/sh

###
# Install OnlyOffice Document Server on FreeBSD (and derivatives)
# Tested on:
# ----------
# 1. FreeBSD 13.1
# Last update: 2022-06-20
# https://github.com/theGeeBee/DocumentServerOnFreeBSD
###

#############################################
###            START OF CONFIG            ###
#############################################

### All fields are required

### Settings for openSSL
###
HOST_NAME="docserver.my.domain"
COUNTRY_CODE="XW" # Example: US/UK/CA/AU/DE, etc.
TIME_ZONE="UTC" # See: https://www.php.net/manual/en/timezones.php

### RabbitMQ settings
###
RMQ_USERNAME="onlyoffice"
RMQ_PASSWORD=$(openssl rand -base64 12)

### PostgreSQL setttings
###
DB_USERNAME="onlyoffice"
DB_PASSWORD=$(openssl rand -base64 16)
DB_NAME="onlyoffice" 


#############################################
###             END OF CONFIG             ###
#############################################


### Check for root privileges
###
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges."
   echo "Type in \`su\` to switch to root and remain in this directory."
   exit 1
fi

### HardenedBSD Check (keeping until after testing on HBSD)
###
r_uname="`uname -r`"
hbsd_test="HBSD"

if test "${r_uname#*$hbsd_test}" != "${r_uname}" # If HBSD is found in uname string
then
	hbsd_test="true"
else 
	hbsd_test="false"
fi 

### Set `pkg` to use LATEST (required for Docserver package!)
###
mkdir -p /usr/local/etc/pkg/repos
echo "FreeBSD: { enabled: no }" > /usr/local/etc/pkg/repos/FreeBSD.conf
cp /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/onlyoffice.conf
sed -i '' "s|quarterly|latest|" /usr/local/etc/pkg/repos/onlyoffice.conf

### Install `pkg`, update repository, upgrade existing packages
###
echo "Installing pkg and updating repositories"
pkg bootstrap -y
pkg update
pkg upgrade -y

### Install required packages
###
cat includes/requirements.txt | xargs pkg install -y

### Add `includes` directory to `supervisord`
###
sed -i '' "s|;[include]|[include]|" /usr/local/etc/supervisord.conf
echo >> "files = /usr/local/etc/onlyoffice/documentserver/supervisor/*.conf"

### Enable services
###
sysrc nginx_enable="YES"
sysrc rabbitmq_enable="YES"
sysrc supervisord_enable="YES"
sysrc postgresql_enable="YES"

### Enable services
###
service postgresql initdb
service postgresql start
service rabbitmq start
service supervisord start

psql -U postgres -c "CREATE DATABASE ${DB_NAME};"
psql -U postgres -c "CREATE USER ${DB_USERNAME} WITH password '${DB_PASSWORD}';"
psql -U postgres -c "GRANT ALL privileges ON DATABASE ${DB_NAME} TO ${DB_USERNAME};"
psql -hlocalhost -U"${DB_USERNAME}" -d "${DB_NAME}" -f /usr/local/www/onlyoffice/documentserver/server/schema/postgresql/createdb.sql

rabbitmqctl --erlang-cookie `cat /var/db/rabbitmq/.erlang.cookie` add_user "${RMQ_USERNAME}" "${RMQ_PASSWORD}"
rabbitmqctl --erlang-cookie `cat /var/db/rabbitmq/.erlang.cookie` set_user_tags "${RMQ_USERNAME}" administrator
rabbitmqctl --erlang-cookie `cat /var/db/rabbitmq/.erlang.cookie` set_permissions -p / onlyoffice ".*" ".*" ".*"
  
### Create self-signed SSL certificate
###
SSL_DIRECTORY="/usr/local/etc/onlyoffice/documentserver/nginx/ssl/"
mkdir -p "${SSL_DIRECTORY}"
OPENSSL_REQUEST="/C=${COUNTRY_CODE}/CN=${HOST_NAME}"
openssl req -x509 -nodes -days 3652 -sha512 -subj ${OPENSSL_REQUEST} -newkey rsa:2048 -keyout ${SSL_DIRECTORY}/docserver.key -out ${SSL_DIRECTORY}/server.crt

### Configure NGINX
###
cp -f "${PWD}"/includes/nginx.conf /usr/local/etc/nginx/
cp -f "${PWD}"/includes/ds-ssl.conf /usr/local/etc/onlyoffice/documentserver/nginx/

### Start NGINX
###
service nginx start

### Create reference file
###
cat >> /root/${HOST_NAME}_reference.txt <<EOL
OnlyOffice Documentserver details:
==================================

RabbitMQ Information:
---------------------
Username : ${RMQ_USERNAME}
Password : ${RMQ_PASSWORD}

Database Information:
---------------------
Database : ${DB_NAME}
Username : ${DB_USERNAME}
Password : ${DB_PASSWORD}

EOL

### All done!
### Print copy of reference info to console
###
clear
echo "Installation Complete!"
echo ""
cat /root/${HOST_NAME}_reference.txt
echo "These details have also been written to /root/${HOST_NAME}_reference.txt"
