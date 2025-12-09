#!/bin/bash
# Handle git pull when local changes exist

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Handling Git Pull with Local Changes"
echo "=========================================="
echo ""

# Check what files have changes
echo "1. Files with local changes:"
git status --short
echo ""

# Check if drachtio-entrypoint.sh has the important :5060 fix
if grep -q ":5060" sbc/drachtio-entrypoint.sh; then
  echo "✅ drachtio-entrypoint.sh has :5060 fix (important!)"
  KEEP_ENTRYPOINT_FIX=true
else
  echo "⚠️  drachtio-entrypoint.sh doesn't have :5060 fix"
  KEEP_ENTRYPOINT_FIX=false
fi
echo ""

echo "2. Stashing local changes..."
git stash push -m "Local changes before pull - drachtio-entrypoint.sh :5060 fix"
echo ""

echo "3. Pulling latest changes..."
git pull
echo ""

echo "4. Restoring important changes..."
if [ "$KEEP_ENTRYPOINT_FIX" = true ]; then
  echo "   Restoring :5060 fix to drachtio-entrypoint.sh..."
  
  # Apply the fix again
  sed -i 's/--contact "sip:${LOCAL_IP};transport=udp"/--contact "sip:${LOCAL_IP}:5060;transport=udp"/' sbc/drachtio-entrypoint.sh
  sed -i 's/--contact "sip:${LOCAL_IP};transport=tcp"/--contact "sip:${LOCAL_IP}:5060;transport=tcp"/' sbc/drachtio-entrypoint.sh
  
  echo "   ✅ Restored :5060 fix"
fi
echo ""

echo "5. Verifying drachtio-entrypoint.sh:"
if grep -q ":5060" sbc/drachtio-entrypoint.sh; then
  echo "   ✅ Has :5060 fix"
  grep "sip:" sbc/drachtio-entrypoint.sh | grep -v "^#"
else
  echo "   ⚠️  Missing :5060 fix - you may need to add it manually"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Restart drachtio-sbc if entrypoint changed:"
echo "   sudo docker compose restart drachtio-sbc"
echo ""
echo "2. Check phone number routing:"
echo "   sudo ./check-phone-number-routing.sh"
echo ""

