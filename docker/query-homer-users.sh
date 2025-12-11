#!/bin/bash
# Query Homer users directly to see what's there

cd "$(dirname "$0")"

echo "=========================================="
echo "Query Homer Users"
echo "=========================================="
echo ""

echo "1. All users in database:"
echo "-------------------------------------------"
sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active, admin, created_date FROM users;" 2>&1
echo ""

echo "2. Users table structure:"
echo "-------------------------------------------"
sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "\d users" 2>&1 | head -30
echo ""

echo "3. Try to see password hash format (if visible):"
echo "-------------------------------------------"
sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, LENGTH(password) as pwd_length, LEFT(password, 10) as pwd_start FROM users LIMIT 5;" 2>&1
echo ""

echo "4. Check if we can create a test user:"
echo "-------------------------------------------"
# Try creating a test user to see if it works
sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "INSERT INTO users (username, password, active, admin) VALUES ('testuser', 'testpass', true, false) ON CONFLICT DO NOTHING;" 2>&1
echo ""

echo "5. Check Homer logs for authentication attempts:"
echo "-------------------------------------------"
sudo docker compose logs homer --tail 20 | grep -iE "auth|login|password|user" | tail -10
echo ""

