#!/bin/bash
set -e

# ===============================
# MongoDB TLS Certificate Generator
# ===============================
# Generates:
#   - Self-signed CA
#   - MongoDB server cert with SAN
#   - Combined PEM for MongoDB
#   - Optional Java TrustStore (JKS)
#
# Supported SAN:
#   - localhost              (host access)
#   - mongodb-tls            (docker short hostname)
#   - mongodb-tls.bankingnet (docker FQDN in network)
# ===============================

# -------- Configurable Variables --------
CONTAINER_NAME="mongodb-tls"
NETWORK_NAME="bankingnet"
VALID_DAYS=3650
TRUSTSTORE_PASS="changeit"

# -------- Folder Setup --------
#mkdir -p ./certs
#cd ./certs

echo "[INFO] Cleaning old certs..."
rm -f ca.* mongodb.* mongo-truststore.jks

# -------- 1. Generate CA Key & Certificate --------
echo "[INFO] Generating CA..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days $VALID_DAYS \
    -out ca.crt \
    -subj "/CN=MyMongoCA"

# -------- 2. Generate Server Key --------
echo "[INFO] Generating MongoDB server key..."
openssl genrsa -out mongodb.key 4096

# -------- 3. Generate CSR with SAN --------
echo "[INFO] Generating CSR with SAN (localhost + Docker names)..."
openssl req -new -key mongodb.key -out mongodb.csr \
    -subj "/CN=${CONTAINER_NAME}" \
    -addext "subjectAltName=DNS:localhost,DNS:${CONTAINER_NAME},DNS:${CONTAINER_NAME}.${NETWORK_NAME}"

# -------- 4. Sign Server Cert with CA and Inline SAN --------
echo "[INFO] Signing server cert with CA..."
openssl x509 -req -in mongodb.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out mongodb.crt -days $VALID_DAYS -sha256 \
    -extfile <(printf "subjectAltName=DNS:localhost,DNS:${CONTAINER_NAME},DNS:${CONTAINER_NAME}.${NETWORK_NAME}")

# -------- 5. Combine PEM for MongoDB --------
cat mongodb.key mongodb.crt > mongodb.pem

echo "[INFO] Certificates generated:"
ls -l ca.* mongodb.*

# -------- 6. Optional: Generate Java TrustStore --------
echo "[INFO] Creating Java truststore for client usage..."
keytool -importcert -trustcacerts \
    -file ca.crt \
    -alias mongodb-ca \
    -keystore mongo-truststore.jks \
    -storepass ${TRUSTSTORE_PASS} -noprompt

echo "[INFO] All done. Files created in certs/:"
ls -l

