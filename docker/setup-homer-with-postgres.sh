#!/bin/bash
# Setup Homer with PostgreSQL (Homer's native database)

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Setting up Homer with PostgreSQL"
echo "=========================================="
echo "⚠️  Homer requires PostgreSQL, not MySQL"
echo ""

# Check if postgres service exists
if grep -q "^  postgres:" docker-compose.yaml; then
  echo "✅ PostgreSQL service already exists"
else
  echo "1. Adding PostgreSQL service..."
  echo "-------------------------------------------"
  
  # Add postgres service
  cat >> docker-compose.yaml << 'EOF'

  postgres:
    image: postgres:15-alpine
    restart: always
    environment:
      POSTGRES_DB: homer
      POSTGRES_USER: homer
      POSTGRES_PASSWORD: homer123
    volumes:
      - ./data_volume/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U homer"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      jambonz:
        ipv4_address: 172.10.0.42
EOF

  echo "✅ Added PostgreSQL service"
fi

echo ""
echo "2. Updating Homer to use PostgreSQL..."
echo "-------------------------------------------"

# Update homer config to use postgres
sed -i.bak '/homer:/,/ipv4_address: 172.10.0.40/ {
  /DB_HOST: mysql/s/DB_HOST: mysql/DB_HOST: postgres/
  /DB_USER: jambones/s/DB_USER: jambones/DB_USER: homer/
  /DB_PASS: jambones/s/DB_PASS: jambones/DB_PASS: homer123/
  /DB_PORT: 3306/s/DB_PORT: 3306/DB_PORT: 5432/
}' docker-compose.yaml

# Update homer depends_on
sed -i.bak2 '/homer:/,/depends_on:/ {
  /depends_on:/a\
      postgres:\
        condition: service_healthy
}' docker-compose.yaml

# Remove mysql from homer depends_on if it's there
sed -i.bak3 '/homer:/,/networks:/ {
  /mysql:/d
}' docker-compose.yaml

echo "✅ Updated Homer configuration"
echo ""

echo "3. Updating webapp_config.json for PostgreSQL..."
echo "-------------------------------------------"
cat > homer/webapp_config.json << 'EOF'
{
  "auth_settings": {
    "token_expire": 1200,
    "type": "internal"
  },
  "database_config": {
    "host": "postgres",
    "keepalive": true,
    "name": "homer",
    "node": "LocalConfig",
    "pass": "homer123",
    "port": 5432,
    "user": "homer"
  },
  "database_data": {
    "localnode": {
      "host": "postgres",
      "keepalive": true,
      "name": "homer",
      "node": "LocalNode",
      "pass": "homer123",
      "port": 5432,
      "user": "homer"
    }
  },
  "http_settings": {
    "debug": false,
    "gzip": true,
    "gzip_static": true,
    "host": "0.0.0.0",
    "port": 80,
    "root": "/usr/local/homer/dist"
  },
  "system_settings": {
    "hostname": "homer",
    "loglevel": "info",
    "logname": "homer-app.log",
    "logpath": "/usr/local/homer/log",
    "logstdout": true
  }
}
EOF
echo "✅ Updated config file"
echo ""

echo "4. Starting PostgreSQL..."
echo "-------------------------------------------"
sudo docker compose up -d postgres
sleep 10
echo ""

echo "5. Starting Homer..."
echo "-------------------------------------------"
sudo docker compose up -d homer
sleep 10
echo ""

echo "6. Checking status..."
echo "-------------------------------------------"
sudo docker compose ps postgres homer
echo ""

echo "7. Checking logs..."
echo "-------------------------------------------"
sudo docker compose logs homer --tail 20
echo ""

echo "=========================================="
echo "Setup Complete"
echo "=========================================="
echo ""
echo "Homer should now be using PostgreSQL."
echo "Access Homer UI: http://localhost:9080"
echo ""

