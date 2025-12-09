#!/bin/bash
# Get Jambonz public IP for Exotel whitelisting

set -e

cd "$(dirname "$0")"

# Get HOST_IP from .env
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
fi

# Try AWS metadata if not found
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

# Try external service as fallback
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
fi

if [ -z "$HOST_IP" ]; then
  echo "❌ Could not determine public IP"
  echo "   Please check your .env file or set HOST_IP manually"
  exit 1
fi

echo "=========================================="
echo "Jambonz Public IP for Exotel Whitelisting"
echo "=========================================="
echo ""
echo "Your Jambonz Public IP:"
echo "  $HOST_IP"
echo ""
echo "=========================================="
echo "Action Required in Exotel Dashboard"
echo "=========================================="
echo ""
echo "1. Go to: Exotel Dashboard → Trunks → Test"
echo ""
echo "2. Click: 'Whitelisted IPs' section"
echo ""
echo "3. Click: 'Add IP addresses'"
echo ""
echo "4. Add this IP: $HOST_IP"
echo ""
echo "5. Save the configuration"
echo ""
echo "=========================================="
echo "Why This Is Critical"
echo "=========================================="
echo ""
echo "Exotel uses IP whitelisting for security."
echo "Without whitelisting your IP, Exotel will:"
echo "  - Reject all SIP INVITEs from Jambonz"
echo "  - Show 'busy' status on calls"
echo "  - Disconnect calls immediately"
echo ""
echo "After whitelisting, calls should work!"
echo ""

