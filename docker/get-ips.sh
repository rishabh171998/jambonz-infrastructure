#!/bin/bash
# Script to get LOCAL_IP and HOST_IP for Docker Compose
# Run this before starting docker compose, or source it

# Get local IP (private IP on EC2)
if [ -z "$LOCAL_IP" ]; then
  # Try AWS metadata service first
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/local-ipv4 > /dev/null 2>&1; then
    LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  # Try GCP metadata service
  elif curl -s --max-time 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip > /dev/null 2>&1; then
    LOCAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
  # Fallback: extract from hostname (e.g., ip-172-31-13-217 -> 172.31.13.217)
  elif HOSTNAME=$(hostname 2>/dev/null) && echo "$HOSTNAME" | grep -q "^ip-"; then
    LOCAL_IP=$(echo "$HOSTNAME" | sed 's/^ip-//' | sed 's/-/./g')
  # Fallback: get first non-loopback IP from hostname -I
  elif HOSTNAME_IP=$(hostname -I 2>/dev/null | awk '{print $1}') && [ -n "$HOSTNAME_IP" ]; then
    LOCAL_IP="$HOSTNAME_IP"
  # Fallback: get from ip route
  elif IP_ROUTE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}') && [ -n "$IP_ROUTE" ]; then
    LOCAL_IP="$IP_ROUTE"
  else
    LOCAL_IP=""
  fi
fi

# Get public IP (HOST_IP)
if [ -z "$HOST_IP" ]; then
  # Try AWS metadata service first
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 > /dev/null 2>&1; then
    HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  # Try GCP metadata service
  elif curl -s --max-time 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip > /dev/null 2>&1; then
    HOST_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
  # Fallback: use external service
  else
    HOST_IP=$(curl -s --max-time 5 http://ipecho.net/plain || curl -s --max-time 5 http://ifconfig.me || curl -s --max-time 5 http://icanhazip.com || echo "")
  fi
fi

# Export for use
export LOCAL_IP
export HOST_IP

echo "LOCAL_IP=${LOCAL_IP}"
echo "HOST_IP=${HOST_IP}"

