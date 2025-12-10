#!/bin/bash
# Check if Exotel Alias format matches Jambonz phone number format

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
echo "Exotel Alias Format Check"
echo "=========================================="
echo ""

echo "1. Phone Numbers in Jambonz Database:"
echo "-------------------------------------------"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number 
FROM phone_numbers 
WHERE number LIKE '%8064061518%' OR number LIKE '%08064061518%' OR number LIKE '%918064061518%'
ORDER BY number;
" 2>/dev/null || echo "")

if [ -n "$PHONE_NUMBERS" ] && ! echo "$PHONE_NUMBERS" | grep -q "Empty set"; then
  echo "$PHONE_NUMBERS"
  echo ""
  echo "Available formats in database:"
  echo "$PHONE_NUMBERS" | grep -v "number" | while read num; do
    echo "  - $num"
  done
else
  echo "❌ No phone numbers found"
fi
echo ""

echo "2. Recent Request URIs from Exotel:"
echo "-------------------------------------------"
RECENT_URIS=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | grep -oE "sip:[0-9]+@" | sed 's/sip://' | sed 's/@//' | sort -u | tail -5 || echo "")

if [ -n "$RECENT_URIS" ]; then
  echo "Phone numbers Exotel is sending in Request URI:"
  for URI in $RECENT_URIS; do
    echo "  - $URI"
    
    # Check if this matches database
    MATCH=$(echo "$PHONE_NUMBERS" | grep -c "^$URI$" || echo "0")
    if [ "$MATCH" -gt 0 ]; then
      echo "    ✅ Matches database"
    else
      echo "    ❌ Does NOT match database"
    fi
  done
else
  echo "No recent INVITEs found"
fi
echo ""

echo "3. Recommended Alias Format:"
echo "-------------------------------------------"
if [ -n "$PHONE_NUMBERS" ] && ! echo "$PHONE_NUMBERS" | grep -q "Empty set"; then
  # Get the most common format (without +)
  RECOMMENDED=$(echo "$PHONE_NUMBERS" | grep -v "number" | head -1 | sed 's/^+//' | sed 's/^0//' || echo "")
  
  if [ -n "$RECOMMENDED" ]; then
    echo "Based on database, use Alias: $RECOMMENDED"
    echo ""
    echo "Or use one of these formats (must match database):"
    echo "$PHONE_NUMBERS" | grep -v "number" | while read num; do
      CLEAN=$(echo "$num" | sed 's/^+//')
      echo "  - $CLEAN"
    done
  fi
else
  echo "Cannot determine - check database first"
fi
echo ""

echo "4. Current Issue:"
echo "-------------------------------------------"
echo "Exotel Alias: 91806406151 (missing last digit '8')"
echo "Phone Number: +918064061518 (complete)"
echo ""
echo "Fix: Update Alias to: 8064061518 (or 918064061518)"
echo ""

echo "=========================================="
echo "Action Required"
echo "=========================================="
echo ""
echo "1. Update Exotel Alias to match phone number format"
echo "2. Update Destination URI to include phone number AND use IP"
echo "3. Add whitelisted IP"
echo ""

