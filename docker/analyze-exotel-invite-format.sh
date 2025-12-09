#!/bin/bash
# Analyze Exotel INVITE format and routing issue

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Exotel INVITE Format Analysis"
echo "=========================================="
echo ""

echo "1. Recent INVITE Request URIs from Exotel:"
echo "-------------------------------------------"
$DOCKER_CMD logs --since 5m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -5 | sed 's/^drachtio-sbc-1  | //' || echo "No recent INVITEs"
echo ""

echo "2. Expected vs Actual Format:"
echo "-------------------------------------------"
echo "❌ Current (from Exotel):"
echo "   INVITE sip:27270013103585148@15.207.113.122"
echo "   INVITE sip:1272500017707497486@15.207.113.122"
echo ""
echo "✅ Should be:"
echo "   INVITE sip:+918064061518@15.207.113.122"
echo "   (or: INVITE sip:08064061518@15.207.113.122)"
echo ""

echo "3. Configured Phone Numbers:"
echo "-------------------------------------------"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE voip_carrier_sid IN (SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%');" 2>/dev/null || echo "No phone numbers found"
echo ""

echo "4. Why 404 Not Found:"
echo "-------------------------------------------"
echo "Jambonz is looking for phone number in the Request URI:"
echo "  - Exotel sends: 27270013103585148 (internal ID)"
echo "  - Jambonz expects: +918064061518 (your phone number)"
echo "  - Result: 404 Not Found (phone number not found)"
echo ""

echo "=========================================="
echo "🔧 FIX REQUIRED IN EXOTEL DASHBOARD"
echo "=========================================="
echo ""
echo "The destination URI in Exotel is still incorrect."
echo ""
echo "Current (WRONG):"
echo "  sip:graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "Should be (CORRECT):"
echo "  sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "OR (if Exotel doesn't support + in URI):"
echo "  sip:918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "OR (without country code):"
echo "  sip:08064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "=========================================="
echo "Steps to Fix:"
echo "=========================================="
echo "1. Go to Exotel Dashboard → Trunk Configuration"
echo "2. Find 'Destination URI' or 'SIP URI' field"
echo "3. Update to include your phone number:"
echo "   sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "4. Save the configuration"
echo "5. Wait 1-2 minutes for changes to propagate"
echo "6. Make a test call"
echo ""
echo "After fixing, you should see INVITEs like:"
echo "  INVITE sip:+918064061518@15.207.113.122"
echo ""

