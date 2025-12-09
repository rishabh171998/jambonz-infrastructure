#!/bin/bash
# Entrypoint script for drachtio-sbc
# LOCAL_IP and HOST_IP should be passed as environment variables from docker-compose

set -e

# Validate that LOCAL_IP and HOST_IP are set
if [ -z "$LOCAL_IP" ]; then
  echo "ERROR: LOCAL_IP environment variable is not set"
  echo "Please set LOCAL_IP in docker-compose.yaml or as environment variable"
  exit 1
fi

if [ -z "$HOST_IP" ]; then
  echo "ERROR: HOST_IP environment variable is not set"
  echo "Please set HOST_IP in docker-compose.yaml or as environment variable"
  exit 1
fi

echo "drachtio-sbc: Using LOCAL_IP=${LOCAL_IP} for binding"
echo "drachtio-sbc: Using HOST_IP=${HOST_IP} for external-ip"

# Build drachtio command with local IP for contact and public IP for external-ip
# This matches the proven Packer configuration
# Note: TLS is omitted as it requires certificates and the public IP binding fails in Docker
exec drachtio \
  --contact "sip:${LOCAL_IP}:5060;transport=udp" \
  --contact "sip:${LOCAL_IP}:5060;transport=tcp" \
  --external-ip "${HOST_IP}" \
  --address "0.0.0.0" \
  --port "9022" \
  --disable-nat-detection \
  "$@"

