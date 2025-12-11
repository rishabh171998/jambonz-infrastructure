#!/bin/bash
# Fix Homer database connection issue

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Database Connection"
echo "=========================================="
echo ""

echo "1. Creating Homer database..."
echo "-------------------------------------------"
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || {
  echo "⚠️  Waiting for MySQL to be ready..."
  sleep 5
  sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || {
    echo "❌ Failed to create database"
    exit 1
  }
}
echo "✅ Database created"
echo ""

echo "2. Granting permissions..."
echo "-------------------------------------------"
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "GRANT ALL PRIVILEGES ON homer.* TO 'jambones'@'%';" 2>/dev/null || echo "⚠️  Permissions may already be set"
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "FLUSH PRIVILEGES;" 2>/dev/null || true
echo "✅ Permissions granted"
echo ""

echo "3. Checking database connection from Homer container..."
echo "-------------------------------------------"
# Test if Homer can reach MySQL
sudo docker compose exec homer ping -c 1 mysql 2>/dev/null && echo "✅ Network connectivity OK" || echo "⚠️  Network issue"

# Test MySQL connection
sudo docker compose exec homer sh -c "nc -z mysql 3306" 2>/dev/null && echo "✅ Port 3306 accessible" || echo "⚠️  Port 3306 not accessible"
echo ""

echo "4. Updating Homer configuration..."
echo "-------------------------------------------"

# The Homer Docker image might need DB_PORT and DB_TYPE
# Let's update docker-compose.yaml to add these
if ! grep -q "DB_PORT" docker-compose.yaml || ! grep -q "DB_TYPE" docker-compose.yaml; then
  echo "Adding DB_PORT and DB_TYPE to Homer configuration..."
  
  # Use sed to add DB_PORT and DB_TYPE after DB_NAME
  sed -i.bak '/homer:/,/ipv4_address: 172.10.0.40/ {
    /DB_NAME: homer/a\
      DB_PORT: 3306\
      DB_TYPE: mysql
  }' docker-compose.yaml
  
  echo "✅ Updated docker-compose.yaml"
  echo ""
  
  echo "5. Restarting Homer..."
  sudo docker compose up -d homer
  sleep 10
else
  echo "✅ Configuration already has DB_PORT/DB_TYPE"
  echo ""
  
  echo "5. Restarting Homer..."
  sudo docker compose restart homer
  sleep 10
fi

echo ""
echo "6. Checking Homer status..."
echo "-------------------------------------------"
sudo docker compose ps homer
echo ""

echo "7. Checking Homer logs..."
echo "-------------------------------------------"
sudo docker compose logs homer --tail 30 | tail -15
echo ""

echo "=========================================="
echo "Fix Complete"
echo "=========================================="
echo ""
echo "If Homer is still failing:"
echo "  1. Check MySQL is accessible: sudo docker compose exec mysql mysql -ujambones -pjambones -e 'SHOW DATABASES;'"
echo "  2. Check Homer logs: sudo docker compose logs homer"
echo "  3. Verify network: sudo docker compose exec homer ping mysql"
echo ""

