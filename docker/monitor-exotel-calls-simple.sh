#!/bin/bash
# Simple commands to monitor Exotel calls

echo "=========================================="
echo "Simple Exotel Call Monitoring Commands"
echo "=========================================="
echo ""

echo "1. Monitor sbc-inbound (routing) - MOST IMPORTANT:"
echo "   sudo docker compose logs -f sbc-inbound"
echo ""

echo "2. Monitor drachtio-sbc (SIP signaling):"
echo "   sudo docker compose logs -f drachtio-sbc | grep -E 'INVITE|8064061518|404|200|BYE'"
echo ""

echo "3. Monitor all services for phone number:"
echo "   sudo docker compose logs -f | grep '8064061518'"
echo ""

echo "4. Check recent errors:"
echo "   sudo docker compose logs --since 5m | grep -iE 'error|fail|rejecting'"
echo ""

echo "5. See full call flow (all SIP messages):"
echo "   sudo docker compose logs -f drachtio-sbc"
echo ""

echo "=========================================="
echo "Quick Status Check"
echo "=========================================="
echo ""

echo "Recent sbc-inbound activity:"
sudo docker compose logs --since 2m sbc-inbound 2>/dev/null | tail -10 | sed 's/^sbc-inbound-1  | //' || echo "No recent activity"

echo ""
echo "Recent SIP messages:"
sudo docker compose logs --since 2m drachtio-sbc 2>/dev/null | grep -E "INVITE.*8064061518|404|200 OK" | tail -5 | sed 's/^drachtio-sbc-1  | //' || echo "No recent SIP activity"

echo ""

