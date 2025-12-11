#!/bin/bash
# Insert API key into database

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
echo "Inserting API Key"
echo "=========================================="
echo ""

API_KEY_SID="3f35518f-5a0d-4c2e-90a5-2407bb3b36f0"
TOKEN="38700987-c7a4-4685-a5bb-af378f9734de"

echo "API Key SID: $API_KEY_SID"
echo "Token: $TOKEN"
echo ""

# Get service provider SID (optional, can be NULL)
SERVICE_PROVIDER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT service_provider_sid 
FROM service_providers 
ORDER BY created_at ASC 
LIMIT 1;
" 2>/dev/null || echo "")

echo "Inserting API key into database..."
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
  ${SERVICE_PROVIDER_SID:+'$SERVICE_PROVIDER_SID'},
  NULL,
  NOW()
);
EOF

if [ $? -eq 0 ]; then
  echo "✅ API key inserted successfully"
else
  echo "❌ Failed to insert API key"
  echo ""
  echo "Trying with minimal fields..."
  
  # Try with just required fields
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO api_keys (
  api_key_sid,
  token,
  created_at
) VALUES (
  '$API_KEY_SID',
  '$TOKEN',
  NOW()
);
EOF
  
  if [ $? -eq 0 ]; then
    echo "✅ API key inserted with minimal fields"
  else
    echo "❌ Still failed. Check error above."
    exit 1
  fi
fi
echo ""

# Verify the token was created
echo "Verifying token..."
VERIFIED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT 
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  created_at
FROM api_keys 
WHERE token = '$TOKEN';
" 2>/dev/null || echo "")

if [ -n "$VERIFIED" ]; then
  echo "✅ Token verified in database:"
  echo "$VERIFIED" | column -t
else
  echo "⚠️  Token not found in database"
fi
echo ""

echo "=========================================="
echo "✅ API Key Created"
echo "=========================================="
echo ""
echo "Token: $TOKEN"
echo ""
echo "Usage in Swagger:"
echo "  1. Go to: http://sip.graine.ai:3000/swagger/"
echo "  2. Click 'Authorize' button (lock icon)"
echo "  3. Enter: Bearer $TOKEN"
echo "  4. Click 'Authorize'"
echo "  5. Click 'Close'"
echo ""
echo "Usage with curl:"
echo "  curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "       http://15.207.113.122:3000/api/v1/Accounts"
echo ""

