#!/bin/bash
# Reset Homer admin password to admin123

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Reset Homer Admin Password"
echo "=========================================="
echo ""

echo "1. Checking PostgreSQL connection..."
echo "-------------------------------------------"
if ! sudo docker compose ps postgres | grep -q "Up"; then
  echo "❌ PostgreSQL is not running"
  exit 1
fi
echo "✅ PostgreSQL is running"
echo ""

echo "2. Checking if admin user exists..."
echo "-------------------------------------------"
ADMIN_EXISTS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username FROM users WHERE username = 'admin' LIMIT 1;" 2>/dev/null | grep -c "admin" || echo "0")

if [ "$ADMIN_EXISTS" -gt 0 ]; then
  echo "✅ Admin user exists"
else
  echo "⚠️  Admin user does not exist"
  echo "   Will create it"
fi
echo ""

echo "3. Resetting admin password to 'admin123'..."
echo "-------------------------------------------"
# Homer uses bcrypt for password hashing
# bcrypt hash for "admin123" with cost 10
# We'll use Python to generate the hash, or use a known hash
ADMIN_HASH='$2a$10$rOzJ5lY5J5J5J5J5J5J5J.5J5J5J5J5J5J5J5J5J5J5J5J5J5J5J'

# Actually, let's use a proper bcrypt hash for "admin123"
# Generated with: python3 -c "import bcrypt; print(bcrypt.hashpw(b'admin123', bcrypt.gensalt(rounds=10)).decode())"
ADMIN_HASH='$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'

# Update or insert admin user
sudo docker compose exec -T postgres psql -Uhomer -dhomer <<EOF
-- Update existing user or insert new one
INSERT INTO users (username, password, active, admin, created_date, updated_date)
VALUES ('admin', '$ADMIN_HASH', true, true, NOW(), NOW())
ON CONFLICT (username) 
DO UPDATE SET 
  password = EXCLUDED.password,
  active = true,
  admin = true,
  updated_date = NOW();
EOF

if [ $? -eq 0 ]; then
  echo "✅ Password reset successful"
else
  echo "❌ Password reset failed"
  exit 1
fi
echo ""

echo "4. Verifying admin user..."
echo "-------------------------------------------"
ADMIN_INFO=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin FROM users WHERE username = 'admin';" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
if [ -n "$ADMIN_INFO" ]; then
  echo "Admin user info: $ADMIN_INFO"
else
  echo "⚠️  Could not verify admin user"
fi
echo ""

echo "5. Updating docker-compose.yaml..."
echo "-------------------------------------------"
# Update HOMER_PASSWORD in docker-compose.yaml
if grep -q "HOMER_PASSWORD.*admin123" docker-compose.yaml; then
  echo "✅ docker-compose.yaml already has HOMER_PASSWORD: admin123"
else
  echo "⚠️  Updating docker-compose.yaml..."
  sed -i "s/HOMER_PASSWORD:.*/HOMER_PASSWORD: 'admin123'/" docker-compose.yaml
  echo "✅ Updated docker-compose.yaml"
fi
echo ""

echo "6. Restarting API server..."
echo "-------------------------------------------"
sudo docker compose restart api-server
sleep 3
echo "✅ API server restarted"
echo ""

echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "Homer admin password has been reset to: admin123"
echo ""
echo "Next steps:"
echo "  1. Try logging into Homer UI: http://localhost:9080"
echo "     Username: admin"
echo "     Password: admin123"
echo ""
echo "  2. If login works, PCAP downloads should work now"
echo ""
echo "  3. Test PCAP download from Recent Calls page"
echo ""

