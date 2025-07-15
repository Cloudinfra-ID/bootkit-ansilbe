#!/bin/bash

set -e

echo "=== CFSSL Certificate Generator ==="
read -rp "Enter Common Name (CN): " CN
read -rp "Enter SAN hosts (comma-separated, e.g. example.com,*.example.com,192.168.1.1): " HOSTS

if [ -z "$CN" ] || [ -z "$HOSTS" ]; then
  echo "❌ CN and Hosts are required. Exiting."
  exit 1
fi

CONFIG_DIR="config"
OUT_DIR="certs"
mkdir -p "$CONFIG_DIR"
mkdir -p "$OUT_DIR"

# Check if CA already exists
if [ -f "$OUT_DIR/ca.pem" ]; then
  echo "✅ CA already exists at '$OUT_DIR/ca.pem'. Skipping CA generation."
else
  echo "→ Generating CA config..."
  cat > "$CONFIG_DIR/ca-csr.json" <<EOF
{
  "CN": "CloudInfra CA",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ID",
      "ST": "Jawa Barat",
      "L": "Jakarta",
      "O": "CloudInfra",
      "OU": "IT"
    }
  ],
  "ca": {
    "expiry": "8760h"
  }
}
EOF

  cat > "$CONFIG_DIR/ca-config.json" <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "server": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF
  echo "→ Generating CA..."
  cfssl gencert -initca "$CONFIG_DIR/ca-csr.json" | cfssljson -bare "$OUT_DIR/ca"
fi

echo "→ Generating server CSR..."
cat > "$CONFIG_DIR/${CN}-csr.json" <<EOF
{
  "CN": "$CN",
  "hosts": [$(echo "$HOSTS" | awk -F',' '{for (i=1; i<=NF; i++) printf "\"%s\"%s", $i, (i<NF?",":"")}')],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "ID",
      "ST": "Jawa Barat",
      "L": "Jakarta",
      "O": "CloudInfra",
      "OU": "IT"
    }
  ]
}
EOF

echo "→ Generating ${CN} server certificate..."
cfssl gencert \
  -ca="$OUT_DIR/ca.pem" \
  -ca-key="$OUT_DIR/ca-key.pem" \
  -config="$CONFIG_DIR/ca-config.json" \
  -profile=server \
  "$CONFIG_DIR/$CN-csr.json" | cfssljson -bare "$OUT_DIR/$CN"

echo "→ Generating ${CN} CA pkcs12 certificate..."
openssl pkcs12 -export -out "${OUT_DIR}/${CN}-ca.p12" \
  -inkey "${OUT_DIR}/ca-key.pem"  \
  -in "${OUT_DIR}/ca.pem" \
  -name "${CN}-ca"

echo "→ Generating ${CN} server pkcs12 certificate..."
openssl pkcs12 -export -out "${OUT_DIR}/${CN}.p12" \
  -inkey "${OUT_DIR}/${CN}-key.pem"  \
  -in "${OUT_DIR}/${CN}.pem" \
  -certfile "${OUT_DIR}/ca.pem" \
  -name "${CN}"

echo "✅ Certificate, key, and CA files are saved in '$OUT_DIR/'"
