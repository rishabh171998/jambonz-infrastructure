#!/bin/bash
# Check if Exotel includes phone number in SIP headers other than Request URI

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel SIP Headers Analysis"
echo "=========================================="
echo ""
echo "Checking recent INVITEs for phone number in headers..."
echo ""

# Get a recent INVITE with full headers
RECENT_INVITE=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep -A 30 "INVITE sip:" | head -40 || echo "")

if [ -z "$RECENT_INVITE" ]; then
  echo "No recent INVITEs found. Make a test call first."
  exit 1
fi

echo "Recent INVITE (full headers):"
echo "-------------------------------------------"
echo "$RECENT_INVITE" | head -30
echo ""

echo "Checking for phone number in various headers:"
echo "-------------------------------------------"

# Check From header
FROM=$(echo "$RECENT_INVITE" | grep -i "^From:" | head -1 || echo "")
if echo "$FROM" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ From header contains phone number:"
  echo "   $FROM"
else
  echo "❌ From header does NOT contain phone number:"
  echo "   $FROM"
fi
echo ""

# Check To header
TO=$(echo "$RECENT_INVITE" | grep -i "^To:" | head -1 || echo "")
if echo "$TO" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ To header contains phone number:"
  echo "   $TO"
else
  echo "❌ To header does NOT contain phone number:"
  echo "   $TO"
fi
echo ""

# Check P-Asserted-Identity
PAI=$(echo "$RECENT_INVITE" | grep -i "P-Asserted-Identity:" | head -1 || echo "")
if [ -n "$PAI" ]; then
  if echo "$PAI" | grep -qE "(918064061518|08064061518)"; then
    echo "✅ P-Asserted-Identity contains phone number:"
    echo "   $PAI"
  else
    echo "⚠️  P-Asserted-Identity exists but no phone number:"
    echo "   $PAI"
  fi
else
  echo "❌ P-Asserted-Identity header not found"
fi
echo ""

# Check Remote-Party-ID
RPI=$(echo "$RECENT_INVITE" | grep -i "Remote-Party-ID:" | head -1 || echo "")
if [ -n "$RPI" ]; then
  if echo "$RPI" | grep -qE "(918064061518|08064061518)"; then
    echo "✅ Remote-Party-ID contains phone number:"
    echo "   $RPI"
  else
    echo "⚠️  Remote-Party-ID exists but no phone number:"
    echo "   $RPI"
  fi
else
  echo "❌ Remote-Party-ID header not found"
fi
echo ""

# Check Contact header
CONTACT=$(echo "$RECENT_INVITE" | grep -i "^Contact:" | head -1 || echo "")
if echo "$CONTACT" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ Contact header contains phone number:"
  echo "   $CONTACT"
else
  echo "❌ Contact header does NOT contain phone number:"
  echo "   $CONTACT"
fi
echo ""

# Check for custom headers
CUSTOM=$(echo "$RECENT_INVITE" | grep -iE "(X-|Custom-|User-)" | head -5 || echo "")
if [ -n "$CUSTOM" ]; then
  echo "Custom headers found:"
  echo "$CUSTOM"
  if echo "$CUSTOM" | grep -qE "(918064061518|08064061518)"; then
    echo "✅ Custom header contains phone number"
  else
    echo "❌ Custom headers do NOT contain phone number"
  fi
else
  echo "❌ No custom headers found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If phone number is found in any header (From, To, P-Asserted-Identity, etc.),"
echo "we can potentially modify Jambonz routing to extract it from there instead"
echo "of the Request URI."
echo ""
echo "If phone number is NOT found in any header, the only solution is to:"
echo "1. Contact Exotel support to configure Request URI format"
echo "2. Use carrier-level application routing (all calls to one app)"
echo ""

