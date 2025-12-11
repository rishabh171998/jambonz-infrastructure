#!/bin/bash
# Check existing API keys and fix/update

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
echo "Checking and Fixing API Key"
echo "=========================================="
echo ""

API_KEY_SID="3f35518f-5a0d-4c2e-90a5-2407bb3b36f0"
TOKEN="38700987-c7a4-4685-a5bb-af378f9734de"

# Check if api_key_sid exists
echo "1. Checking if API key SID exists..."
EXISTING_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT api_key_sid 
FROM api_keys 
WHERE api_key_sid = '$API_KEY_SID';
" 2>/dev/null || echo "")

if [ -n "$EXISTING_SID" ]; then
  echo "   ⚠️  API key SID already exists: $API_KEY_SID"
  echo ""
  echo "   Current record:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT 
    api_key_sid,
    token,
    account_sid,
    service_provider_sid,
    expires_at,
    created_at
  FROM api_keys 
  WHERE api_key_sid = '$API_KEY_SID';
  " 2>/dev/null
  echo ""
  
  echo "   Options:"
  echo "   1. Update existing record with new token"
  echo "   2. Create new API key with different SID"
  echo ""
  read -p "   Choose option (1 or 2, default: 1): " OPTION
  OPTION=${OPTION:-1}
  
  if [ "$OPTION" = "1" ]; then
    echo ""
    echo "   Updating existing API key with new token..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE api_keys 
SET 
  token = '$TOKEN',
  expires_at = NULL,
  last_used = NULL
WHERE api_key_sid = '$API_KEY_SID';
EOF
    
    if [ $? -eq 0 ]; then
      echo "   ✅ API key updated successfully"
    else
      echo "   ❌ Failed to update API key"
      exit 1
    fi
  else
    echo ""
    echo "   Creating new API key with different SID..."
    NEW_API_KEY_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    echo "   New API Key SID: $NEW_API_KEY_SID"
    
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO api_keys (
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  created_at
) VALUES (
  '$NEW_API_KEY_SID',
  '$TOKEN',
  NULL,
  NULL,
  NULL,
  NOW()
);
EOF
    
    if [ $? -eq 0 ]; then
      echo "   ✅ New API key created successfully"
      API_KEY_SID=$NEW_API_KEY_SID
    else
      echo "   ❌ Failed to create new API key"
      exit 1
    fi
  fi
else
  echo "   ✅ API key SID does not exist, creating new record..."
  echo ""
  
  # Check if token already exists
  EXISTING_TOKEN=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT token 
  FROM api_keys 
  WHERE token = '$TOKEN';
  " 2>/dev/null || echo "")
  
  if [ -n "$EXISTING_TOKEN" ]; then
    echo "   ⚠️  Token already exists, updating record..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE api_keys 
SET 
  api_key_sid = '$API_KEY_SID',
  expires_at = NULL,
  last_used = NULL
WHERE token = '$TOKEN';
EOF
  else
    echo "   Creating new API key..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO api_keys (
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  created_at
) VALUES (
  '$API_KEY_SID',
  '$TOKEN',
  NULL,
  NULL,
  NULL,
  NOW()
);
EOF
  fi
  
  if [ $? -eq 0 ]; then
    echo "   ✅ API key created successfully"
  else
    echo "   ❌ Failed to create API key"
    exit 1
  fi
fi

echo ""

# Verify the token
echo "2. Verifying API key..."
VERIFIED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  created_at,
  last_used
FROM api_keys 
WHERE token = '$TOKEN';
" 2>/dev/null || echo "")

if [ -n "$VERIFIED" ]; then
  echo "   ✅ Token verified:"
  echo "$VERIFIED"
else
  echo "   ⚠️  Token not found"
fi
echo ""

echo "=========================================="
echo "✅ API Key Ready"
echo "=========================================="
echo ""
echo "Token: $TOKEN"
echo ""
echo "Usage in Swagger:"
echo "  1. Go to: http://sip.graine.ai:3000/swagger/"
echo "  2. Click 'Authorize' button (lock icon at top)"
echo "  3. Enter: Bearer $TOKEN"
echo "  4. Click 'Authorize'"
echo "  5. Click 'Close'"
echo ""
echo "Usage with curl:"
echo "  curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "       http://15.207.113.122:3000/api/v1/Accounts"
echo ""

