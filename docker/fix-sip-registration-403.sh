#!/bin/bash
# Fix SIP registration 403 Forbidden

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
echo "Fix SIP Registration 403 Forbidden"
echo "=========================================="
echo ""

# Extract registration details from recent logs
REGISTER_INFO=$($DOCKER_CMD logs --tail 100 drachtio-sbc 2>/dev/null | grep "REGISTER sip:" | tail -1 || echo "")

if [ -z "$REGISTER_INFO" ]; then
  echo "❌ No recent REGISTER requests found in logs"
  echo "   Make a registration attempt first"
  exit 1
fi

# Extract username and domain
USERNAME=$(echo "$REGISTER_INFO" | grep -oE "From: \"[^\"]+\"" | sed 's/From: "//' | sed 's/"//' | head -1 || echo "")
DOMAIN=$(echo "$REGISTER_INFO" | grep -oE "sip:[^@]+@([^ ]+)" | head -1 | cut -d'@' -f2 | cut -d' ' -f1 || echo "")

if [ -z "$USERNAME" ] || [ -z "$DOMAIN" ]; then
  echo "⚠️  Could not extract username/domain from logs"
  echo ""
  echo "Please provide:"
  read -p "Username (e.g., 5001): " USERNAME
  read -p "Domain (e.g., 15.207.113.122 or graineone.sip.graine.ai): " DOMAIN
fi

echo "Username: $USERNAME"
echo "Domain: $DOMAIN"
echo ""

# Ensure clients table exists
echo "0. Ensuring clients table exists..."
echo "-------------------------------------------"
TABLE_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT COUNT(*) 
FROM information_schema.tables 
WHERE table_schema = 'jambones' 
AND table_name = 'clients';
" 2>/dev/null || echo "0")

if [ "$TABLE_EXISTS" != "1" ]; then
  echo "   Creating clients table..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
CREATE TABLE IF NOT EXISTS clients (
  client_sid CHAR(36) NOT NULL UNIQUE,
  account_sid CHAR(36) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT 1,
  username VARCHAR(64),
  password VARCHAR(1024),
  allow_direct_app_calling BOOLEAN NOT NULL DEFAULT 1,
  allow_direct_queue_calling BOOLEAN NOT NULL DEFAULT 1,
  allow_direct_user_calling BOOLEAN NOT NULL DEFAULT 1,
  PRIMARY KEY (client_sid),
  INDEX account_sid_idx (account_sid),
  INDEX username_idx (username)
);
EOF
  if [ $? -eq 0 ]; then
    echo "   ✅ Clients table created"
  else
    echo "   ❌ Failed to create clients table"
    exit 1
  fi
else
  echo "   ✅ Clients table exists"
fi
echo ""

# Find account by SIP realm
echo "1. Finding Account by SIP Realm..."
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE sip_realm = '$DOMAIN' OR sip_realm LIKE '%$DOMAIN%'
LIMIT 1;
" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  echo "   ⚠️  No account found with SIP realm: $DOMAIN"
  echo ""
  echo "   Available accounts:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT account_sid, name, sip_realm 
  FROM accounts 
  WHERE sip_realm IS NOT NULL AND sip_realm != '';
  " 2>/dev/null | head -10
  
  echo ""
  read -p "Enter account_sid to use: " ACCOUNT_SID
else
  echo "   ✅ Found account: $ACCOUNT_SID"
fi
echo ""

# Check if client exists
echo "2. Checking SIP Client..."
echo "-------------------------------------------"
CLIENT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT client_sid 
FROM clients 
WHERE username = '$USERNAME' AND account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

if [ -z "$CLIENT_SID" ]; then
  echo "   ⚠️  Client not found for username: $USERNAME"
  echo ""
  read -p "Create new client? (y/n): " CREATE_CLIENT
  
  if [ "$CREATE_CLIENT" = "y" ] || [ "$CREATE_CLIENT" = "Y" ]; then
    read -p "Password for $USERNAME: " PASSWORD
    if [ -z "$PASSWORD" ]; then
      echo "❌ Password required"
      exit 1
    fi
    
    CLIENT_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    
    echo ""
    echo "Creating client..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO clients (
  client_sid,
  account_sid,
  username,
  password,
  is_active,
  allow_direct_app_calling,
  allow_direct_queue_calling,
  allow_direct_user_calling
) VALUES (
  '$CLIENT_SID',
  '$ACCOUNT_SID',
  '$USERNAME',
  '$PASSWORD',
  1,
  1,
  1,
  1
);
EOF
    
    if [ $? -eq 0 ]; then
      echo "   ✅ Client created: $CLIENT_SID"
    else
      echo "   ❌ Failed to create client"
      exit 1
    fi
  else
    echo "   Client not created. Registration will fail without client or webhook."
    exit 1
  fi
else
  echo "   ✅ Client found: $CLIENT_SID"
  
  # Check if client is active
  IS_ACTIVE=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT is_active 
  FROM clients 
  WHERE client_sid = '$CLIENT_SID';
  " 2>/dev/null || echo "")
  
  if [ "$IS_ACTIVE" = "0" ]; then
    echo "   ⚠️  Client is INACTIVE"
    read -p "Activate client? (y/n): " ACTIVATE
    
    if [ "$ACTIVATE" = "y" ] || [ "$ACTIVATE" = "Y" ]; then
      $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
      UPDATE clients 
      SET is_active = 1 
      WHERE client_sid = '$CLIENT_SID';
      "
      echo "   ✅ Client activated"
    fi
  else
    echo "   ✅ Client is active"
  fi
fi
echo ""

# Check registration webhook
echo "3. Checking Registration Webhook..."
echo "-------------------------------------------"
REG_HOOK=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT registration_hook_sid 
FROM accounts 
WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

if [ -z "$REG_HOOK" ] || [ "$REG_HOOK" = "NULL" ]; then
  echo "   ⚠️  No registration webhook configured"
  echo ""
  echo "   Options:"
  echo "   1. Use client credentials (already created above)"
  echo "   2. Configure registration webhook in webapp"
  echo ""
  echo "   With client credentials, registration should work now"
else
  echo "   ✅ Registration webhook configured: $REG_HOOK"
  
  HOOK_URL=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT url 
  FROM webhooks 
  WHERE webhook_sid = '$REG_HOOK';
  " 2>/dev/null || echo "")
  
  if [ -n "$HOOK_URL" ]; then
    echo "   Webhook URL: $HOOK_URL"
    echo ""
    echo "   ⚠️  If webhook returns failure, registration will be rejected"
    echo "   Check webhook logs to ensure it returns status: 'ok'"
  fi
fi
echo ""

# Restart registrar
echo "4. Restarting Registrar Service..."
echo "-------------------------------------------"
$DOCKER_CMD restart registrar
sleep 3
echo "   ✅ Registrar restarted"
echo ""

echo "=========================================="
echo "✅ Registration Fix Complete"
echo "=========================================="
echo ""
echo "Client Details:"
echo "  Username: $USERNAME"
echo "  Account: $ACCOUNT_SID"
echo "  Domain: $DOMAIN"
echo ""
echo "Try registering again. If still getting 403:"
echo "  1. Verify password is correct"
echo "  2. Check registration webhook (if configured) returns 'ok'"
echo "  3. Check registrar logs: sudo docker compose logs -f registrar"
echo ""

