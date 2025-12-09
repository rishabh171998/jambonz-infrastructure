#!/bin/bash
# Check phone number routing configuration

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Phone Number Routing Check"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "Exotel Carrier SID: $CARRIER_SID"
echo ""

# Check phone number 08064061518
PHONE="08064061518"
echo "1. Checking phone number: $PHONE"
echo ""

# Try different formats
for PHONE_FORMAT in "08064061518" "+918064061518" "918064061518"; do
  PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT phone_number_sid, number, voip_carrier_sid, application_sid, account_sid FROM phone_numbers WHERE number = '$PHONE_FORMAT';" 2>/dev/null | grep -v "phone_number_sid" || echo "")
  
  if [ -n "$PHONE_INFO" ] && [ "$PHONE_INFO" != "" ]; then
    echo "   Found: $PHONE_INFO"
    echo ""
    
    # Extract application_sid
    APP_SID=$(echo "$PHONE_INFO" | awk '{print $4}')
    
    if [ -z "$APP_SID" ] || [ "$APP_SID" = "NULL" ]; then
      echo "   ❌ PROBLEM: Phone number has NO application assigned"
      echo "   This is why you're getting 404 Not Found"
      echo ""
      echo "   FIX: In webapp → Phone Numbers → Edit $PHONE_FORMAT"
      echo "        Assign an Application"
    else
      echo "   ✅ Phone number has application: $APP_SID"
      
      # Check if application exists
      APP_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM applications WHERE application_sid = '$APP_SID';" 2>/dev/null)
      if [ "$APP_EXISTS" = "1" ]; then
        echo "   ✅ Application exists"
      else
        echo "   ❌ Application $APP_SID does not exist!"
      fi
    fi
    break
  fi
done

echo ""

# Check carrier default application
echo "2. Checking carrier default application:"
CARRIER_APP=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT application_sid FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
if [ -n "$CARRIER_APP" ] && [ "$CARRIER_APP" != "NULL" ]; then
  echo "   ✅ Carrier has default application: $CARRIER_APP"
  echo "   (This is used if phone number has no application)"
else
  echo "   ⚠️  Carrier has NO default application"
  echo "   (Phone number must have application assigned)"
fi
echo ""

# List all applications
echo "3. Available Applications:"
APPS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT application_sid, name, account_sid FROM applications LIMIT 10;" 2>/dev/null | grep -v "application_sid" || echo "  (none)")
echo "$APPS"
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "To fix 404 Not Found:"
echo ""
echo "Option 1: Assign application to phone number (Recommended)"
echo "  1. Go to: Phone Numbers → Edit $PHONE"
echo "  2. Select an Application from dropdown"
echo "  3. Save"
echo ""
echo "Option 2: Set default application on carrier"
echo "  1. Go to: Carriers → Exotel → General"
echo "  2. Set 'Application for incoming calls'"
echo "  3. Save"
echo ""
echo "After assigning application, test call again!"
echo ""

