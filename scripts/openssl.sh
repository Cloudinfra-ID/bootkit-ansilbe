#!/bin/bash

# Generating OpenSSL Self-signed certs with SANs support
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout ./vault.key \
  -out ./vault.crt \
  -config openssl.cnf
