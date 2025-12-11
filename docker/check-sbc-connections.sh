
#!/bin/bash
# Quick check of SBC service connections

cd "$(dirname "$0")"

echo "=========================================="
echo "SBC Connection Status"
echo "=========================================="
echo ""

echo "1. Service Status:"
echo "-------------------------------------------"
sudo docker compose ps drachtio-sbc sbc-inbound sbc-outbound call-router registrar feature-server | grep -E "NAME|drachtio|sbc|call-router|registrar|feature"
echo ""

echo "2. Recent drachtio-sbc connection logs:"
echo "-------------------------------------------"
sudo docker compose logs drachtio-sbc --tail 30 | grep -iE "client.*connect|client.*disconnect|sbc-inbound|sbc-outbound|registrar" | tail -10 || echo "No connection messages found"
echo ""

echo "3. Checking if services are trying to connect:"
echo "-------------------------------------------"
echo "sbc-inbound logs:"
sudo docker compose logs sbc-inbound --tail 10 | grep -iE "connect|drachtio|error" | tail -5 || echo "No logs"
echo ""
echo "sbc-outbound logs:"
sudo docker compose logs sbc-outbound --tail 10 | grep -iE "connect|drachtio|error" | tail -5 || echo "No logs"
echo ""

echo "4. Testing OPTIONS handling:"
echo "-------------------------------------------"
echo "The OPTIONS request from FreeSWITCH is normal (health check)"
echo "But drachtio-sbc needs connected clients to handle it."
echo ""
echo "If you see 'No connected clients', the SBC services need to connect."
echo ""

