#!/bin/sh
# Vuelve el directorio al seed original: recrea los contenedores LDAP, que no guardan
# datos en volúmenes. Lo que se haya creado o editado desde LAM se pierde.
#
# Uso (desde la carpeta vps/):  sh scripts/reset.sh
set -eu

cd "$(dirname "$0")/.."
docker compose up -d --force-recreate \
    ldap ldap-chain ldap-chain-no-intermediate ldap-self-signed ldap-self-signed-leaf ldap-expired
echo "Directorio reiniciado con el seed."
