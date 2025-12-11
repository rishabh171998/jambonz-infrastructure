#!/bin/bash
# Fix Homer admin user with correct table structure

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Admin User (Correct Structure)"
echo "=========================================="
echo ""

echo "1. Checking users table structure..."
echo "-------------------------------------------"
TABLE_COLS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "\d users" 2>&1 | grep -E "^\s+\w+\s+\|" | awk '{print $1}' | tr '\n' ',' || echo "")
echo "Table columns: $TABLE_COLS"
echo ""

# Get full structure
FULL_STRUCT=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "\d users" 2>&1)
echo "Full table structure:"
echo "$FULL_STRUCT" | head -30
echo ""

echo "2. Checking existing users (with correct columns)..."
echo "-------------------------------------------"
# Try to get all data without specifying column names that might not exist
ALL_USERS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT * FROM users LIMIT 5;" 2>&1 || echo "")
if [ -n "$ALL_USERS" ]; then
  echo "Existing users data:"
  echo "$ALL_USERS"
else
  echo "⚠️  Could not query users or table is empty"
fi
echo ""

echo "3. Getting column names dynamically..."
echo "-------------------------------------------"
COLUMNS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position;" 2>&1 | grep -v "column_name\|row\|---" | tr '\n' ',' | sed 's/,$//' || echo "")
echo "Actual columns: $COLUMNS"
echo ""

echo "4. Creating/updating admin user with correct structure..."
echo "-------------------------------------------"
# Based on Homer's structure, it likely has: username, password, admin (boolean), created_date, updated_date
# Let's try a minimal insert
sudo docker compose exec -T postgres psql -Uhomer -dhomer <<'SQL'
-- Delete existing admin if exists
DELETE FROM users WHERE username = 'admin';

-- Insert admin user
-- Using bcrypt hash for "admin123": $2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy
INSERT INTO users (username, password, admin, created_date, updated_date)
VALUES (
  'admin',
  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
  true,
  NOW(),
  NOW()
);
SQL

if [ $? -eq 0 ]; then
  echo "✅ Admin user created"
else
  echo "❌ Failed - trying with minimal fields..."
  
  # Try with just username and password
  sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "DELETE FROM users WHERE username = 'admin'; INSERT INTO users (username, password) VALUES ('admin', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy');" 2>&1
fi
echo ""

echo "5. Verifying admin user..."
echo "-------------------------------------------"
ADMIN_CHECK=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username FROM users WHERE username = 'admin';" 2>&1 | grep "admin" | head -1 || echo "")
if [ -n "$ADMIN_CHECK" ]; then
  echo "✅ Admin user exists: $ADMIN_CHECK"
  
  # Show full admin user record
  ADMIN_FULL=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT * FROM users WHERE username = 'admin';" 2>&1 | grep -v "row\|---" | head -2 || echo "")
  echo "Full admin record:"
  echo "$ADMIN_FULL"
else
  echo "❌ Admin user still not found"
fi
echo ""

echo "6. Alternative: Try empty password or different passwords..."
echo "-------------------------------------------"
echo "If the password hash doesn't work, try these in Homer UI:"
echo "  - Username: admin, Password: (empty)"
echo "  - Username: admin, Password: admin"
echo "  - Username: admin, Password: sipcapture"
echo ""

echo "7. Restarting Homer to pick up changes..."
echo "-------------------------------------------"
sudo docker compose restart homer
sleep 5
echo "✅ Homer restarted"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Try logging into Homer UI:"
echo "   http://localhost:9080"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "2. If that doesn't work, try:"
echo "   - Password: (empty)"
echo "   - Password: admin"
echo "   - Password: sipcapture"
echo ""
echo "3. Check Homer logs for authentication:"
echo "   sudo docker compose logs homer | grep -i auth"
echo ""

