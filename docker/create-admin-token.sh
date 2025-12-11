#!/bin/bash
# Create admin API token for Swagger authentication

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
echo "Creating Admin API Token"
echo "=========================================="
echo ""

# Generate a UUID token
TOKEN=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' || openssl rand -hex 16)

echo "Generated Token: $TOKEN"
echo ""

# Get service provider SID (usually the default one)
SERVICE_PROVIDER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT service_provider_sid 
FROM service_providers 
ORDER BY created_at ASC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -z "$SERVICE_PROVIDER_SID" ]; then
  echo "⚠️  No service provider found, creating token without service_provider_sid"
  SERVICE_PROVIDER_SID="NULL"
else
  echo "Service Provider SID: $SERVICE_PROVIDER_SID"
fi
echo ""

# Create API key
echo "Creating API key in database..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO api_keys (
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  created_at
) VALUES (
  UUID(),
  '$TOKEN',
  NULL,
  ${SERVICE_PROVIDER_SID:-NULL},
  NULL,
  NOW()
);
EOF

if [ $? -eq 0 ]; then
  echo "✅ API key created successfully"
else
  echo "❌ Failed to create API key"
  exit 1
fi
echo ""

# Verify the token was created
echo "Verifying token..."
VERIFIED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT token 
FROM api_keys 
WHERE token = '$TOKEN';
" 2>/dev/null || echo "")

if [ -n "$VERIFIED" ]; then
  echo "✅ Token verified in database"
else
  echo "⚠️  Token not found in database"
fi
echo ""

echo "=========================================="
echo "✅ Admin Token Created"
echo "=========================================="
echo ""
echo "Token: $TOKEN"
echo ""
echo "Usage:"
echo "  1. In Swagger UI:"
echo "     - Click 'Authorize' button"
echo "     - Enter: Bearer $TOKEN"
echo "     - Click 'Authorize'"
echo ""
echo "  2. With curl:"
echo "     curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "          http://15.207.113.122:3000/api/v1/Accounts"
echo ""
echo "  3. Save this token securely - it won't be shown again!"
echo ""

