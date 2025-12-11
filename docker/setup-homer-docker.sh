#!/bin/bash
# Setup Homer in Docker for Jambonz PCAP functionality

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Setting up Homer in Docker"
echo "=========================================="
echo ""

# Check if docker-compose.yaml exists
if [ ! -f "docker-compose.yaml" ]; then
  echo "❌ docker-compose.yaml not found"
  exit 1
fi

# Check if Homer is already configured
if grep -q "homer:" docker-compose.yaml; then
  echo "⚠️  Homer service already exists in docker-compose.yaml"
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
  fi
fi

echo "1. Adding Homer service to docker-compose.yaml..."
echo "-------------------------------------------"

# Create backup
cp docker-compose.yaml docker-compose.yaml.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Created backup: docker-compose.yaml.backup.*"

# Add Homer service (we'll use the official Homer Docker image)
HOMER_SERVICE='
  homer:
    image: sipcapture/webapp:latest
    restart: always
    ports:
      - "9080:9080"
    environment:
      DB_HOST: mysql
      DB_USER: jambones
      DB_PASS: jambones
      DB_NAME: homer
      HOMER_USER: admin
      HOMER_PASS: admin123
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      jambonz:
        ipv4_address: 172.10.0.40
'

# Add heplify-server for capturing SIP traffic
HEPLIFY_SERVICE='
  heplify-server:
    image: sipcapture/heplify-server:latest
    restart: always
    ports:
      - "9060:9060/udp"  # HEP port
      - "3050:3050"      # WebSocket port
    environment:
      DB_HOST: mysql
      DB_USER: jambones
      DB_PASS: jambones
      DB_NAME: homer
    depends_on:
      mysql:
        condition: service_healthy
      homer:
        condition: service_started
    networks:
      jambonz:
        ipv4_address: 172.10.0.41
'

# Check if we need to add these services
if ! grep -q "homer:" docker-compose.yaml; then
  # Find the last service and add before it closes
  # We'll add it after the webapp service
  if grep -q "webapp:" docker-compose.yaml; then
    # Insert after webapp service
    awk -v homer="$HOMER_SERVICE" -v heplify="$HEPLIFY_SERVICE" '
      /^  webapp:/ { 
        print; 
        while (getline > 0 && /^[[:space:]]/) { print } 
        print homer; 
        print heplify; 
        print 
      } 
      { print }
    ' docker-compose.yaml > docker-compose.yaml.tmp
    mv docker-compose.yaml.tmp docker-compose.yaml
    echo "✅ Added Homer and heplify-server services"
  else
    echo "⚠️  Could not find insertion point, adding at end"
    echo "$HOMER_SERVICE" >> docker-compose.yaml
    echo "$HEPLIFY_SERVICE" >> docker-compose.yaml
  fi
fi

echo ""
echo "2. Updating API server environment variables..."
echo "-------------------------------------------"

# Update api-server to include Homer config
if ! grep -q "HOMER_BASE_URL" docker-compose.yaml; then
  # Add Homer env vars to api-server
  sed -i.bak '/api-server:/a\
    environment:\
      <<: *common-variables\
      HTTP_PORT: 3000\
      HOMER_BASE_URL: '\''http://homer:9080'\''\
      HOMER_USERNAME: '\''admin'\''\
      HOMER_PASSWORD: '\''admin123'\''
' docker-compose.yaml 2>/dev/null || {
    # Alternative approach - use a more targeted sed
    awk '
      /^  api-server:/ { 
        print; 
        getline; 
        print; 
        if ($0 ~ /environment:/) { 
          print "      HOMER_BASE_URL: '\''http://homer:9080'\''"
          print "      HOMER_USERNAME: '\''admin'\''"
          print "      HOMER_PASSWORD: '\''admin123'\''"
        }
      } 
      { print }
    ' docker-compose.yaml > docker-compose.yaml.tmp
    mv docker-compose.yaml.tmp docker-compose.yaml
  }
  echo "✅ Added Homer environment variables to api-server"
else
  echo "⚠️  HOMER_BASE_URL already exists in api-server"
fi

echo ""
echo "3. Creating Homer database..."
echo "-------------------------------------------"

# Create homer database in MySQL
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer;" 2>/dev/null || echo "⚠️  Could not create database (may already exist)"

echo ""
echo "4. Starting Homer services..."
echo "-------------------------------------------"

sudo docker compose up -d homer heplify-server

echo ""
echo "5. Waiting for services to be ready..."
sleep 10

echo ""
echo "6. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps homer heplify-server

echo ""
echo "=========================================="
echo "Homer Setup Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Restart API server: sudo docker compose restart api-server"
echo "  2. Verify Homer is accessible: curl http://localhost:9080"
echo "  3. Check Homer logs: sudo docker compose logs homer"
echo "  4. Test PCAP download in webapp"
echo ""
echo "Homer Web UI: http://localhost:9080"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Note: You may need to configure SIP capture to send data to heplify-server"
echo "      (port 9060 UDP) for PCAP files to be available."
echo ""

