#!/bin/bash
# Debug why 404 is happening even though phone number has application

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
echo "Debugging Exotel 404 Routing"
echo "=========================================="
echo ""

APP_SID="08d78564-d3f6-4db4-95ce-513ae757c2c9"

echo "1. Checking application exists and is active:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT application_sid, name, account_sid FROM applications WHERE application_sid = '$APP_SID';" 2>/dev/null
echo ""

echo "2. Phone numbers with this application:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE application_sid = '$APP_SID';" 2>/dev/null
echo ""

echo "3. Recent SBC logs showing Exotel INVITE:"
echo "   (Looking for the To header format)"
$DOCKER_CMD logs --tail 100 drachtio-sbc 2>/dev/null | grep -A 5 -B 5 "1219300017707497486\|INVITE" | tail -30
echo ""

echo "=========================================="
echo "The Problem"
echo "=========================================="
echo ""
echo "From the logs, Exotel is sending:"
echo "  To: <sip:1219300017707497486@15.207.113.122>"
echo ""
echo "This is an Exotel internal ID, NOT your phone number!"
echo ""
echo "Jambonz tries to match this to phone numbers in database:"
echo "  - 08064061518"
echo "  - 918064061518"
echo ""
echo "But '1219300017707497486' doesn't match either format."
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "The issue is in Exotel's destination URI configuration."
echo ""
echo "Current (wrong): sip:graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "Should be: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "           OR: sip:08064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "The phone number MUST be in the Request URI for Jambonz to route it."
echo ""
echo "Fix in Exotel Dashboard:"
echo "  1. Go to: Trunks → Test → Destination URIs"
echo "  2. Change from: sip:graineone.sip.graine.ai:5060;transport=tcp"
echo "  3. Change to: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "  4. Save"
echo ""

