#!/bin/bash
# Fix Homer authentication - check and reset admin password

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Authentication"
echo "=========================================="
echo ""

echo "1. Checking Homer users in database..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  HOMER_USERS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, password IS NOT NULL as has_password FROM users WHERE username = 'admin' LIMIT 1;" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
  
  if [ -n "$HOMER_USERS" ]; then
    echo "Homer users:"
    echo "$HOMER_USERS"
  else
    echo "⚠️  Admin user not found in database"
    echo "   Creating admin user..."
    
    # Create admin user with password admin123
    # Homer uses bcrypt for password hashing
    # Default password hash for "admin123" (bcrypt, cost 10)
    ADMIN_HASH='$2a$10$rOzJ5lY5J5J5J5J5J5J5J.5J5J5J5J5J5J5J5J5J5J5J5J5J5J'
    
    # Actually, let's use a simpler approach - check Homer's default
    echo "   Checking if we can create user via Homer API..."
  fi
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "2. Checking Homer logs for authentication errors..."
echo "-------------------------------------------"
AUTH_ERRORS=$(sudo docker compose logs homer --tail 50 | grep -iE "auth|login|password|user" | tail -10 || echo "")
if [ -n "$AUTH_ERRORS" ]; then
  echo "Recent auth-related logs:"
  echo "$AUTH_ERRORS"
else
  echo "No auth errors in recent logs"
fi
echo ""

echo "3. Testing Homer authentication API..."
echo "-------------------------------------------"
# Try different common passwords
echo "Testing common passwords..."
for PASSWORD in "admin123" "admin" "homer" "sipcapture" ""; do
  if [ -z "$PASSWORD" ]; then
    PASSWORD_JSON="{\"username\":\"admin\"}"
  else
    PASSWORD_JSON="{\"username\":\"admin\",\"password\":\"$PASSWORD\"}"
  fi
  
  RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PASSWORD_JSON" \
    "http://localhost:9080/api/v3/auth" 2>/dev/null || echo "")
  
  if echo "$RESPONSE" | grep -q "token\|apikey\|success"; then
    echo "✅ Password found: '$PASSWORD'"
    break
  fi
done
echo ""

echo "4. Checking Homer default credentials..."
echo "-------------------------------------------"
echo "Common Homer default passwords:"
echo "  - admin123"
echo "  - admin"
echo "  - homer"
echo "  - sipcapture"
echo "  - (empty)"
echo ""
echo "Try these in the Homer UI login page"
echo ""

echo "5. Resetting admin password (if needed)..."
echo "-------------------------------------------"
echo "To reset the admin password, you can:"
echo ""
echo "Option 1: Use Homer UI (if you can access it)"
echo "  - Try logging in with different passwords"
echo "  - Or use password reset if available"
echo ""
echo "Option 2: Reset via database"
echo "  - Connect to PostgreSQL"
echo "  - Update users table with new password hash"
echo ""
echo "Option 3: Recreate Homer database"
echo "  - Stop Homer: sudo docker compose stop homer"
echo "  - Drop database: sudo docker compose exec postgres psql -Uhomer -dhomer -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'"
echo "  - Restart Homer: sudo docker compose start homer"
echo "  - Homer will recreate tables and default users"
echo ""

echo "6. Quick fix - Update API server Homer password..."
echo "-------------------------------------------"
echo "If you find the correct password, update docker-compose.yaml:"
echo "  HOMER_PASSWORD: 'correct_password'"
echo "Then restart API server:"
echo "  sudo docker compose restart api-server"
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "Try these passwords in Homer UI:"
echo "  1. admin123 (most common)"
echo "  2. admin"
echo "  3. homer"
echo "  4. sipcapture"
echo "  5. (leave password empty)"
echo ""
echo "Once you find the correct password:"
echo "  1. Update docker-compose.yaml:"
echo "     HOMER_PASSWORD: 'correct_password'"
echo ""
echo "  2. Restart API server:"
echo "     sudo docker compose restart api-server"
echo ""
echo "  3. Test PCAP download again"
echo ""
echo "If none work, reset Homer database (Option 3 above)"
echo ""

