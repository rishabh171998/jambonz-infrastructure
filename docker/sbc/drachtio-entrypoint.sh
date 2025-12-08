#!/bin/bash
# Entrypoint script for drachtio-sbc to get local IP for binding
# This matches the proven Packer configuration

set -e

# Get local IP (private IP on EC2)
# Try AWS metadata first, then fallback to hostname -I
if [ -z "$LOCAL_IP" ]; then
  # Try AWS metadata service
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/local-ipv4 > /dev/null 2>&1; then
    LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  # Try GCP metadata service
  elif curl -s --max-time 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip > /dev/null 2>&1; then
    LOCAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
  # Fallback: get first non-loopback IP from host
  else
    LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "172.10.0.10")
  fi
fi

# Get public IP (HOST_IP should be set, but fallback to metadata)
if [ -z "$HOST_IP" ]; then
  # Try AWS metadata service
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 > /dev/null 2>&1; then
    HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  # Try GCP metadata service
  elif curl -s --max-time 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip > /dev/null 2>&1; then
    HOST_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
  # Fallback: use LOCAL_IP if no public IP found
  else
    HOST_IP="${LOCAL_IP}"
  fi
fi

echo "drachtio-sbc: Using LOCAL_IP=${LOCAL_IP} for binding"
echo "drachtio-sbc: Using HOST_IP=${HOST_IP} for external-ip"

# Build drachtio command with local IP for contact and public IP for external-ip
# This matches the proven Packer configuration
exec drachtio \
  --contact "sip:${LOCAL_IP};transport=udp" \
  --contact "sip:${LOCAL_IP};transport=tcp" \
  --contact "sip:${LOCAL_IP};transport=tls" \
  --external-ip "${HOST_IP}" \
  --address "0.0.0.0" \
  --port "9022" \
  --disable-nat-detection \
  "$@"

