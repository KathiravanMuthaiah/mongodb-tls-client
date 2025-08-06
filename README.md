

# MongoDB TLS Setup on Ubuntu

This guide demonstrates how to configure **MongoDB with TLS** on an Ubuntu machine using a **self-signed CA**.  
The setup includes:

- Self-signed **Certificate Authority (CA)**
- MongoDB **server certificate** with SAN entries
- **Combined PEM file** for `mongod`
- Optional **Java TrustStore** for TLS client connections

---

## 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y mongodb openssl default-jdk


```

## 2. Create Certificates

```bash
#!/bin/bash
set -e

# Configurable Variables
CONTAINER_NAME="mongodb-tls"
NETWORK_NAME="bankingnet"
VALID_DAYS=3650
TRUSTSTORE_PASS="changeit"

mkdir -p ./certs
cd ./certs

echo "[INFO] Cleaning old certs..."
rm -f ca.* mongodb.* mongo-truststore.jks

# 1. Generate CA
echo "[INFO] Generating CA..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days $VALID_DAYS \
    -out ca.crt \
    -subj "/CN=MyMongoCA"

# 2. Generate MongoDB Server Key
echo "[INFO] Generating server key..."
openssl genrsa -out mongodb.key 4096

# 3. Generate CSR with SAN
echo "[INFO] Generating CSR with SAN..."
openssl req -new -key mongodb.key -out mongodb.csr \
    -subj "/CN=${CONTAINER_NAME}" \
    -addext "subjectAltName=DNS:localhost,DNS:${CONTAINER_NAME},DNS:${CONTAINER_NAME}.${NETWORK_NAME}"

# 4. Sign Server Certificate with CA and SAN
echo "[INFO] Signing server cert..."
openssl x509 -req -in mongodb.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out mongodb.crt -days $VALID_DAYS -sha256 \
    -extfile <(printf "subjectAltName=DNS:localhost,DNS:${CONTAINER_NAME},DNS:${CONTAINER_NAME}.${NETWORK_NAME}")

# 5. Combine PEM for MongoDB
cat mongodb.key mongodb.crt > mongodb.pem
chmod 600 mongodb.key mongodb.pem

# 6. Optional: Create Java TrustStore
echo "[INFO] Creating truststore..."
keytool -importcert -trustcacerts \
    -file ca.crt \
    -alias mongodb-ca \
    -keystore mongo-truststore.jks \
    -storepass ${TRUSTSTORE_PASS} -noprompt

echo "[INFO] Done. Generated files:"
ls -l ca.* mongodb.* mongo-truststore.jks
```
### Understanding SAN (Subject Alternative Name) in MongoDB TLS

  #### 1. What is SAN?

- **SAN (Subject Alternative Name)** is an extension to X.509 certificates.
- It allows a single certificate to **declare multiple valid identities** for the same service.
- SAN entries can include:
  - **DNS Names** → e.g., `localhost`, `mongodb-tls`, `mongodb-tls.bankingnet`
  - **IP Addresses** → e.g., `127.0.0.1` or Docker bridge IP
  - **Email or URI** → rarely used in MongoDB setups
  ------
  #### 2. Why we need SAN?
- Modern clients **no longer trust the CN (Common Name) alone**.

- Without SAN, MongoDB clients like `mongosh` may fail TLS handshake with:

  SSL peer certificate validation failed: certificate name mismatch

  #### 2.1 What We Did in Our Setup
  
  In our setup, we generated a **self-signed CA** and a **server certificate** with SAN entries that cover:
  
  1. **localhost** →  
   - Allows local testing on the same machine without DNS resolution.
  
  2. **mongodb-tls** →  
   - Docker container’s **hostname** on the bridge network.
  
  3. **mongodb-tls.bankingnet** →  
   - Fully Qualified Domain Name (FQDN) on the custom Docker network `bankingnet`.
  
  This ensures:
  - The same PEM certificate works for **host connections, container-to-container, and network FQDN**.
  - TLS clients validate the server cert successfully, as long as they connect using one of the SAN entries.
  
  ------
  
  #### 3. How We Implemented SAN
  
  **Step 1: Create CSR with SAN**  
  We used `openssl req` with `-addext` for SAN:
  
  ```bash
  openssl req -new -key mongodb.key -out mongodb.csr \
  -subj "/CN=mongodb-tls" \
  -addext "subjectAltName=DNS:localhost,DNS:mongodb-tls,DNS:mongodb-tls.bankingnet"
  ```

  **Step 2: Sign the certificate with SAN**

  ```bash
  openssl x509 -req -in mongodb.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out mongodb.crt -days 3650 -sha256 \
    -extfile <(printf "subjectAltName=DNS:localhost,DNS:mongodb-tls,DNS:mongodb-tls.bankingnet")
  ```

  ------

  #### 4. Why This Is Important

  - If the **MongoDB client connects using a name not in SAN**, TLS validation fails.
  - SAN ensures the **certificate is valid for multiple access patterns**, including:
    - **`mongo --host localhost`**
    - **`mongo --host mongodb-tls`** (from another container)
    - **`mongo --host mongodb-tls.bankingnet`** (Docker network FQDN)

  > **Tip:** For production, include your actual DNS name or server IP in SAN.

  ------

  #### 5. Learning Outcome

  - **SAN is critical for TLS in modern MongoDB deployments.**
  - Always list **all the hostnames and IPs** your MongoDB clients will use.
  - This prevents certificate mismatch errors and ensures **seamless TLS handshake**.

------
## 3. Start MongoDB with TLS

```bash
mongod \
  --dbpath /data/db \
  --logpath /var/log/mongodb/mongod.log \
  --bind_ip 0.0.0.0 \
  --port 27017 \
  --tlsMode requireTLS \
  --tlsCertificateKeyFile ./certs/mongodb.pem \
  --tlsCAFile ./certs/ca.crt \
  --tlsAllowConnectionsWithoutCertificates
```

Giving --tlsAllowConnectionsWithoutCertificates states that the server can connect to any system without client side SSL available. Which means it is not a MTLS just TLS. Remember that if we do want to use MTLS server should also know about the client certificate chain. So we might need to use proper client side SSL certificate properly signed by known CA or we need to supply the CA certificate to server to get added to its server CA repository.

------

## 4. Connect MongoDB Client with TLS

```bash
mongo --host localhost --port 27017 \
  --tls \
  --tlsCAFile ./certs/ca.crt
```

> **Note:**
>
> - If mutual TLS is required, also provide `--tlsCertificateKeyFile ./certs/mongodb.pem` on the client.
> - For containerized setups, ensure `mongodb.pem` is mounted and readable inside the container.
> - Here if we do not have the server certificate then we need to add --tlsAllowInvalidCertificates in the command to ignore server certificate.

------

## 5. Verification

- Check that MongoDB is using TLS:

```bash
openssl s_client -connect localhost:27017 -CAfile ./certs/ca.crt
```

- MongoDB log should show lines like:

```text
[conn1] connection accepted from 127.0.0.1:...
[conn1] connection authenticated using X.509
```

------

## ✅ Summary

1. Generated CA, server key, and server cert with SAN.
2. Combined `.key` + `.crt` → `mongodb.pem`.
3. Started `mongod` with `requireTLS`.
4. Connected with `mongo` using TLS.

This setup is **sufficient for local testing** and **Docker-based TLS networks** like `bankingnet`.
 For **production**, use a real CA and **do not use** `--tlsAllowConnectionsWithoutCertificates` and --tlsAllowInvalidCertificates.
