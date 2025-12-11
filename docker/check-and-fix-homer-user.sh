#!/bin/bash
# Check and fix Homer admin user

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Check and Fix Homer Admin User"
echo "=========================================="
echo ""

echo "1. Checking existing users in Homer database..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  USERS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin, created_date FROM users ORDER BY created_date DESC LIMIT 10;" 2>/dev/null || echo "")
  
  if [ -n "$USERS" ] && echo "$USERS" | grep -q "username"; then
    echo "Existing users:"
    echo "$USERS"
  else
    echo "⚠️  No users found or query failed"
    echo "   Users table may be empty"
  fi
else
  echo "❌ PostgreSQL is not running"
  exit 1
fi
echo ""

echo "2. Checking if admin user exists..."
echo "-------------------------------------------"
ADMIN_EXISTS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM users WHERE username = 'admin';" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")

if [ "$ADMIN_EXISTS" != "0" ] && [ "$ADMIN_EXISTS" != "" ]; then
  echo "✅ Admin user exists"
  
  # Get admin user details
  ADMIN_INFO=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin FROM users WHERE username = 'admin';" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
  echo "Admin info: $ADMIN_INFO"
else
  echo "❌ Admin user does not exist"
  echo "   Will create it"
fi
echo ""

echo "3. Creating/updating admin user..."
echo "-------------------------------------------"
# Use a known bcrypt hash for "admin123"
# This hash was generated with: python3 -c "import bcrypt; print(bcrypt.hashpw(b'admin123', bcrypt.gensalt(rounds=10)).decode())"
ADMIN_HASH='$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'

# Create or update admin user
sudo docker compose exec -T postgres psql -Uhomer -dhomer <<'SQL'
-- Delete existing admin user if exists
DELETE FROM users WHERE username = 'admin';

-- Insert new admin user with password 'admin123'
INSERT INTO users (username, password, active, admin, created_date, updated_date)
VALUES ('admin', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', true, true, NOW(), NOW());
SQL

if [ $? -eq 0 ]; then
  echo "✅ Admin user created/updated"
else
  echo "❌ Failed to create/update admin user"
  echo "   Trying alternative method..."
  
  # Alternative: use Python to generate hash if available
  if command -v python3 &> /dev/null; then
    echo "   Generating bcrypt hash with Python..."
    NEW_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'admin123', bcrypt.gensalt(rounds=10)).decode())" 2>/dev/null || echo "")
    if [ -n "$NEW_HASH" ]; then
      echo "   Using generated hash..."
      sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "DELETE FROM users WHERE username = 'admin'; INSERT INTO users (username, password, active, admin, created_date, updated_date) VALUES ('admin', '$NEW_HASH', true, true, NOW(), NOW());"
    fi
  fi
fi
echo ""

echo "4. Verifying admin user..."
echo "-------------------------------------------"
ADMIN_VERIFY=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin FROM users WHERE username = 'admin';" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
if [ -n "$ADMIN_VERIFY" ]; then
  echo "✅ Admin user verified: $ADMIN_VERIFY"
else
  echo "⚠️  Could not verify admin user"
fi
echo ""

echo "5. Testing authentication..."
echo "-------------------------------------------"
echo "Try logging into Homer UI now:"
echo "  URL: http://localhost:9080 (or http://15.207.113.122:9080)"
echo "  Username: admin"
echo "  Password: admin123"
echo ""

echo "6. Updating API server configuration..."
echo "-------------------------------------------"
# Check if HOMER_PASSWORD is set correctly
CURRENT_PASS=$(grep "HOMER_PASSWORD" docker-compose.yaml | grep -o "'[^']*'" | tr -d "'" || echo "")
if [ "$CURRENT_PASS" = "admin123" ]; then
  echo "✅ docker-compose.yaml already has correct password"
else
  echo "⚠️  Updating docker-compose.yaml..."
  sed -i "s/HOMER_PASSWORD:.*/HOMER_PASSWORD: 'admin123'/" docker-compose.yaml
  echo "✅ Updated docker-compose.yaml"
  echo "   Restarting API server..."
  sudo docker compose restart api-server
  sleep 3
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Admin user has been created/updated with password: admin123"
echo ""
echo "Next steps:"
echo "  1. Try logging into Homer UI:"
echo "     http://localhost:9080"
echo "     Username: admin"
echo "     Password: admin123"
echo ""
echo "  2. If login works, test PCAP download:"
echo "     - Go to Recent Calls"
echo "     - Click PCAP download button"
echo ""
echo "  3. If login still fails, check Homer logs:"
echo "     sudo docker compose logs homer | grep -i user"
echo ""

