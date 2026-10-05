#!/bin/sh
# Levanta el LDAP de QA: genera los certificados si faltan (o si cambió LDAP_HOST),
# arma la página de info y levanta los contenedores.
#
# Uso (desde la carpeta vps/):  sh scripts/up.sh
#   REGENERATE=1 sh scripts/up.sh   regenera los certificados de servidor (la CA se conserva)
set -eu

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "Falta .env: copiá .env.example a .env y completalo."
    exit 1
fi
set -a
. ./.env
set +a

mkdir -p data/certs data/site
if [ "${REGENERATE:-0}" = "1" ] \
    || [ ! -f data/certs/valid/server.crt ] \
    || [ "$(cat data/certs/.host 2>/dev/null)" != "$LDAP_HOST" ]; then
    echo "Generando certificados para ${LDAP_HOST}..."
    docker run --rm -e LDAP_HOST="$LDAP_HOST" \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -v "$(pwd)/scripts:/scripts:ro" -v "$(pwd)/data/certs:/out" \
        alpine:3.20 sh /scripts/generate_certs.sh
    echo "$LDAP_HOST" > data/certs/.host
fi

sh scripts/build_site.sh
docker compose up -d --force-recreate

cat <<INFO

LDAP de QA levantado.
  Página de info : 127.0.0.1:${INFO_PORT:-8041}  (publicar como https://${LDAP_HOST}/)
  LAM            : 127.0.0.1:${LAM_PORT:-8040}  (publicar como https://${LAM_HOST}/)
  Usuario web    : ${WEB_USER}
INFO
