#!/bin/bash
# Diagnose SIP registration 403 Forbidden errors

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
echo "SIP Registration 403 Forbidden Diagnostic"
echo "=========================================="
echo ""

# 1. Check recent REGISTER attempts
echo "1. Recent REGISTER Attempts:"
echo "-------------------------------------------"
REGISTER_ATTEMPTS=$($DOCKER_CMD logs --tail 50 drachtio-sbc 2>/dev/null | grep -iE "REGISTER|403 Forbidden" | tail -10 || echo "")
if [ -n "$REGISTER_ATTEMPTS" ]; then
  echo "$REGISTER_ATTEMPTS" | sed 's/^/   /'
else
  echo "   No recent REGISTER attempts found"
fi
echo ""

# 2. Extract registration details from logs
echo "2. Registration Details from Logs:"
echo "-------------------------------------------"
REGISTER_INFO=$($DOCKER_CMD logs --tail 100 drachtio-sbc 2>/dev/null | grep "REGISTER sip:" | tail -1 || echo "")
if [ -n "$REGISTER_INFO" ]; then
  echo "   $REGISTER_INFO"
  
  # Extract username and domain
  USERNAME=$(echo "$REGISTER_INFO" | grep -oE "From: \"[^\"]+\"" | sed 's/From: "//' | sed 's/"//' || echo "")
  DOMAIN=$(echo "$REGISTER_INFO" | grep -oE "sip:[^@]+@([^ ]+)" | cut -d'@' -f2 | cut -d' ' -f1 || echo "")
  
  if [ -n "$USERNAME" ]; then
    echo "   Username: $USERNAME"
  fi
  if [ -n "$DOMAIN" ]; then
    echo "   Domain: $DOMAIN"
  fi
else
  echo "   Could not extract registration details"
fi
echo ""

# 3. Check accounts with SIP realm matching
echo "3. Accounts with SIP Realm:"
echo "-------------------------------------------"
if [ -n "$DOMAIN" ]; then
  MATCHING_ACCOUNTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT 
    account_sid,
    name,
    sip_realm
  FROM accounts 
  WHERE sip_realm = '$DOMAIN' OR sip_realm LIKE '%$DOMAIN%';
  " 2>/dev/null || echo "")
  
  if [ -n "$MATCHING_ACCOUNTS" ] && ! echo "$MATCHING_ACCOUNTS" | grep -q "Empty set"; then
    echo "$MATCHING_ACCOUNTS"
  else
    echo "   ⚠️  No account found with SIP realm: $DOMAIN"
    echo ""
    echo "   All accounts and their SIP realms:"
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
    SELECT account_sid, name, sip_realm 
    FROM accounts 
    WHERE sip_realm IS NOT NULL AND sip_realm != '';
    " 2>/dev/null | head -20
  fi
else
  echo "   All accounts with SIP realms:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT account_sid, name, sip_realm 
  FROM accounts 
  WHERE sip_realm IS NOT NULL AND sip_realm != '';
  " 2>/dev/null | head -20
fi
echo ""

# 4. Check clients (SIP users) for the account
echo "4. SIP Clients (Users):"
echo "-------------------------------------------"
if [ -n "$USERNAME" ]; then
  CLIENT_CHECK=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT 
    client_sid,
    account_sid,
    username,
    is_active
  FROM clients 
  WHERE username = '$USERNAME';
  " 2>/dev/null || echo "")
  
  if [ -n "$CLIENT_CHECK" ] && ! echo "$CLIENT_CHECK" | grep -q "Empty set"; then
    echo "$CLIENT_CHECK"
  else
    echo "   ⚠️  No client found with username: $USERNAME"
    echo ""
    echo "   All clients:"
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
    SELECT client_sid, account_sid, username, is_active 
    FROM clients 
    LIMIT 10;
    " 2>/dev/null | head -15
  fi
else
  echo "   All clients:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT client_sid, account_sid, username, is_active 
  FROM clients 
  LIMIT 10;
  " 2>/dev/null | head -15
fi
echo ""

# 5. Check registration webhook configuration
echo "5. Registration Webhook Configuration:"
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE sip_realm = '$DOMAIN' OR sip_realm LIKE '%$DOMAIN%'
LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  REG_HOOK=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT registration_hook_sid 
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
  " 2>/dev/null || echo "")
  
  if [ -n "$REG_HOOK" ] && [ "$REG_HOOK" != "NULL" ]; then
    echo "   ✅ Registration webhook configured: $REG_HOOK"
    
    HOOK_URL=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
    SELECT url 
    FROM webhooks 
    WHERE webhook_sid = '$REG_HOOK';
    " 2>/dev/null || echo "")
    
    if [ -n "$HOOK_URL" ]; then
      echo "   Webhook URL: $HOOK_URL"
    fi
  else
    echo "   ⚠️  No registration webhook configured"
    echo "   Registration requires either:"
    echo "     1. Registration webhook configured"
    echo "     2. Client credentials in database"
  fi
else
  echo "   ⚠️  Could not find account for domain: $DOMAIN"
fi
echo ""

# 6. Check registrar service logs
echo "6. Registrar Service Logs:"
echo "-------------------------------------------"
REGISTRAR_LOGS=$($DOCKER_CMD logs --tail 50 registrar 2>/dev/null | grep -iE "register|403|error|$USERNAME" | tail -10 || echo "")
if [ -n "$REGISTRAR_LOGS" ]; then
  echo "$REGISTRAR_LOGS" | sed 's/^/   /'
else
  echo "   No recent registrar logs found"
fi
echo ""

echo "=========================================="
echo "Common Causes of 403 Forbidden"
echo "=========================================="
echo ""
echo "1. No registration webhook configured"
echo "2. Client credentials not in database"
echo "3. SIP realm mismatch"
echo "4. Client is_active = 0"
echo "5. Registration webhook returning failure"
echo ""

