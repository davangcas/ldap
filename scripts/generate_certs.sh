#!/bin/sh
# Generates the certificates the local LDAP test server presents, one set per
# scenario, plus the CA the administrator loads in the platform.
#
# Runs inside a throwaway Alpine container launched by scripts/up.sh, so the
# host does not need openssl. Writes to /out, owned by HOST_UID:HOST_GID.
#
# The test CAs are kept between runs: the administrator pasted ca.crt in the LDAP
# configuration, and a new one would make that configuration stop connecting.
#
# Output (data/certs/ on the VPS):
#   ca.crt / ca.key   CA that signs the `valid`, `chain` and `expired` certificates
#   other-ca.crt      unrelated CA, to check that loading the wrong one fails
#   valid/            server certificate signed by ca.crt, names LDAP_HOST only
#   chain/            server certificate signed by an intermediate CA, which the
#                     server sends along; the administrator still loads ca.crt
#   chain-no-intermediate/
#                     same certificate, but the server does not send the
#                     intermediate: ca.crt alone fails, ca.crt plus the
#                     intermediate connects
#   self-signed/      self-signed server certificate, same names
#   self-signed-leaf/ self-signed server certificate that is not a CA
#                     (CA:FALSE), as most server tools generate it
#   expired/          server certificate signed by ca.crt, already expired
set -eu

apk add --no-cache openssl >/dev/null

SERVER_NAME="${LDAP_HOST:?LDAP_HOST is required}"
OUT=/out
WORK=$(mktemp -d)
cd "$WORK"

# Without a config of its own, `openssl req` would add the distribution's default
# extensions, and -addext then fails on the duplicates.
cat > req.cnf <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = placeholder
CNF

cat > server.ext <<EXT
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${SERVER_NAME}
EXT

cat > intermediate.ext <<'EXT'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
EXT

new_ca() {
    openssl req -config req.cnf -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$1.key" -out "$1.crt" -subj "/CN=$2" \
        -addext "basicConstraints = critical, CA:TRUE" \
        -addext "keyUsage = critical, keyCertSign, cRLSign" 2>/dev/null
}

new_csr() {
    openssl req -config req.cnf -newkey rsa:2048 -nodes \
        -keyout "$1.key" -out "$1.csr" -subj "/CN=$2" 2>/dev/null
}

if [ -f "$OUT/ca.crt" ] && [ -f "$OUT/ca.key" ]; then
    cp "$OUT/ca.crt" "$OUT/ca.key" .
else
    new_ca ca "SMARTFENSE LDAP Test CA"
fi
if [ -f "$OUT/other-ca.crt" ]; then
    cp "$OUT/other-ca.crt" .
else
    new_ca other-ca "Otra CA de prueba"
fi

new_csr valid "$SERVER_NAME"
openssl x509 -req -in valid.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 825 -extfile server.ext -out valid.crt 2>/dev/null

new_csr intermediate "SMARTFENSE LDAP Test Intermediate CA"
openssl x509 -req -in intermediate.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 1825 -extfile intermediate.ext -out intermediate.crt 2>/dev/null
new_csr chain "$SERVER_NAME"
openssl x509 -req -in chain.csr -CA intermediate.crt -CAkey intermediate.key \
    -CAcreateserial -days 825 -extfile server.ext -out chain-leaf.crt 2>/dev/null
# The server presents its certificate followed by the intermediate, as a real
# directory does; the client only trusts the root.
cat chain-leaf.crt intermediate.crt > chain.crt
cp chain-leaf.crt chain-no-intermediate.crt
cp chain.key chain-no-intermediate.key

openssl req -config req.cnf -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout self-signed.key -out self-signed.crt -subj "/CN=${SERVER_NAME}" \
    -addext "basicConstraints = critical, CA:TRUE" \
    -addext "keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign" \
    -addext "extendedKeyUsage = serverAuth" \
    -addext "subjectAltName = DNS:${SERVER_NAME}" 2>/dev/null

openssl req -config req.cnf -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout self-signed-leaf.key -out self-signed-leaf.crt -subj "/CN=${SERVER_NAME}" \
    -addext "basicConstraints = CA:FALSE" \
    -addext "keyUsage = critical, digitalSignature, keyEncipherment" \
    -addext "extendedKeyUsage = serverAuth" \
    -addext "subjectAltName = DNS:${SERVER_NAME}" 2>/dev/null

# `openssl x509 -req` cannot backdate a certificate; `openssl ca` can.
mkdir newcerts && touch index.txt && echo 1000 > serial
cat > ca.cnf <<'CNF'
[ca]
default_ca = test_ca
[test_ca]
database = index.txt
new_certs_dir = newcerts
serial = serial
default_md = sha256
policy = any
unique_subject = no
[any]
commonName = supplied
CNF
new_csr expired "$SERVER_NAME"
openssl ca -batch -notext -config ca.cnf -cert ca.crt -keyfile ca.key \
    -in expired.csr -out expired.crt -extfile server.ext \
    -startdate 20200101000000Z -enddate 20200201000000Z 2>/dev/null

# The DH parameters slapd needs. The standard ffdhe2048 group is instant, and it
# comes out in the PKCS#3 format GnuTLS reads; `dhparam -dsaparam` does not.
openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 -out dhparam.pem

for scenario in valid chain chain-no-intermediate self-signed self-signed-leaf expired; do
    rm -rf "${OUT:?}/$scenario"
    mkdir -p "$OUT/$scenario"
    cp "$scenario.crt" "$OUT/$scenario/server.crt"
    cp "$scenario.key" "$OUT/$scenario/server.key"
    cp dhparam.pem "$OUT/$scenario/dhparam.pem"
done
cp ca.crt ca.key other-ca.crt intermediate.crt "$OUT/"
# slapd wants a CA file next to its certificate; a self-signed one is its own CA.
cp ca.crt "$OUT/valid/ca.crt"
cp ca.crt "$OUT/chain/ca.crt"
cp ca.crt "$OUT/chain-no-intermediate/ca.crt"
cp ca.crt "$OUT/expired/ca.crt"
cp self-signed.crt "$OUT/self-signed/ca.crt"
cp self-signed-leaf.crt "$OUT/self-signed-leaf/ca.crt"

chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"
chmod -R u=rwX,go=rX "$OUT"
chmod 600 "$OUT/ca.key" "$OUT"/*/server.key
echo "Certificados generados en ldap-test-data/certs/"
