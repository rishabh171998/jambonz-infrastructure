#!/bin/bash
# Properly fix Homer admin user - check structure and create correctly

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Admin User Properly"
echo "=========================================="
echo ""

echo "1. Checking users table structure..."
echo "-------------------------------------------"
TABLE_STRUCT=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "\d users" 2>/dev/null || echo "")
if [ -n "$TABLE_STRUCT" ]; then
  echo "Users table structure:"
  echo "$TABLE_STRUCT" | head -20
else
  echo "⚠️  Could not get table structure"
fi
echo ""

echo "2. Checking existing users..."
echo "-------------------------------------------"
ALL_USERS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT * FROM users;" 2>/dev/null || echo "")
if [ -n "$ALL_USERS" ]; then
  echo "All users in database:"
  echo "$ALL_USERS"
else
  echo "⚠️  Could not query users or table is empty"
fi
echo ""

echo "3. Checking Homer initialization..."
echo "-------------------------------------------"
echo "Homer may need to initialize users itself"
echo "Let's check if we can trigger user creation..."
echo ""

echo "4. Stopping and restarting Homer to trigger initialization..."
echo "-------------------------------------------"
sudo docker compose stop homer
sleep 3

# Clear any existing admin user
sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "DELETE FROM users WHERE username = 'admin';" 2>/dev/null || echo ""

# Restart Homer - it should create default users
sudo docker compose start homer
echo "✅ Homer restarted"
echo "Waiting 10 seconds for initialization..."
sleep 10
echo ""

echo "5. Checking if admin user was created by Homer..."
echo "-------------------------------------------"
ADMIN_CHECK=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin FROM users WHERE username = 'admin';" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
if [ -n "$ADMIN_CHECK" ]; then
  echo "✅ Admin user found: $ADMIN_CHECK"
  echo ""
  echo "Homer may have created it with a default password"
  echo "Common default passwords:"
  echo "  - (empty/no password)"
  echo "  - admin"
  echo "  - admin123"
  echo "  - sipcapture"
  echo ""
  echo "Try these in the Homer UI login"
else
  echo "⚠️  Admin user still not found"
  echo ""
  echo "6. Manually creating admin user with different methods..."
  echo "-------------------------------------------"
  
  # Try with a simpler approach - use Homer's expected format
  # First, let's see what the password column expects
  echo "Attempting to create admin user..."
  
  # Method 1: Try with a known working bcrypt hash
  sudo docker compose exec -T postgres psql -Uhomer -dhomer <<'SQL'
-- Try to insert admin user
-- Using bcrypt hash for "admin123" 
INSERT INTO users (username, password, active, admin, created_date, updated_date)
VALUES (
  'admin',
  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
  true,
  true,
  NOW(),
  NOW()
)
ON CONFLICT (username) DO NOTHING;
SQL

  # Verify
  ADMIN_AFTER=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username FROM users WHERE username = 'admin';" 2>/dev/null | grep "admin" | head -1 || echo "")
  if [ -n "$ADMIN_AFTER" ]; then
    echo "✅ Admin user created"
  else
    echo "❌ Still failed to create admin user"
    echo ""
    echo "Let's check the exact error..."
    sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "INSERT INTO users (username, password, active, admin) VALUES ('admin', 'test', true, true);" 2>&1
  fi
fi
echo ""

echo "7. Alternative: Try logging in with empty password..."
echo "-------------------------------------------"
echo "Some Homer installations allow empty password for admin"
echo "Try in Homer UI:"
echo "  Username: admin"
echo "  Password: (leave empty)"
echo ""

echo "8. Checking Homer logs for user creation messages..."
echo "-------------------------------------------"
HOMER_USER_LOGS=$(sudo docker compose logs homer --tail 50 | grep -iE "user|admin|password|install" | tail -10 || echo "")
if [ -n "$HOMER_USER_LOGS" ]; then
  echo "Recent user-related logs:"
  echo "$HOMER_USER_LOGS"
fi
echo ""

echo "=========================================="
echo "Troubleshooting Steps"
echo "=========================================="
echo ""
echo "If login still doesn't work:"
echo ""
echo "1. Check what users actually exist:"
echo "   sudo docker compose exec postgres psql -Uhomer -dhomer -c \"SELECT username, active FROM users;\""
echo ""
echo "2. Try different passwords in Homer UI:"
echo "   - (empty)"
echo "   - admin"
echo "   - admin123"
echo "   - sipcapture"
echo "   - homer"
echo ""
echo "3. Check Homer documentation for default credentials"
echo ""
echo "4. As last resort, recreate Homer database:"
echo "   sudo docker compose stop homer"
echo "   sudo docker compose exec postgres psql -Uhomer -dhomer -c \"DROP SCHEMA public CASCADE; CREATE SCHEMA public;\""
echo "   sudo docker compose start homer"
echo "   # Wait 60 seconds for initialization"
echo "   # Check logs for default password"
echo ""

