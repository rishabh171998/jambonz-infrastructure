#!/bin/bash
# Add Homer services to docker-compose.yaml

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Adding Homer to Docker Compose"
echo "=========================================="
echo ""

# Create backup
cp docker-compose.yaml docker-compose.yaml.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Created backup"

# Check if homer already exists
if grep -q "^  homer:" docker-compose.yaml; then
  echo "⚠️  Homer service already exists"
  exit 0
fi

# Find where to insert (after webapp service, before the end)
# We'll add it after the last service

# Read the file and add Homer services
python3 << 'PYTHON_SCRIPT'
import re

with open('docker-compose.yaml', 'r') as f:
    content = f.read()

# Check if homer already exists
if 'homer:' in content:
    print("Homer already exists in docker-compose.yaml")
    exit(0)

# Add Homer service after webapp
homer_service = '''
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

  heplify-server:
    image: sipcapture/heplify-server:latest
    restart: always
    ports:
      - "9060:9060/udp"
      - "3050:3050"
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
'''

# Find the last service and add after it
# Look for the pattern of a service definition followed by its config
# We'll add after webapp service if it exists, otherwise after the last service

if 'webapp:' in content:
    # Insert after webapp service block
    pattern = r'(  webapp:.*?ipv4_address: \d+\.\d+\.\d+\.\d+\n)'
    replacement = r'\1' + homer_service
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)
else:
    # Add at the end before networks or at the very end
    if 'networks:' in content:
        content = content.replace('networks:', homer_service + '\nnetworks:')
    else:
        content += homer_service

# Update api-server to include Homer env vars
if 'HOMER_BASE_URL' not in content:
    # Find api-server environment section and add Homer vars
    api_env_pattern = r'(  api-server:.*?environment:\s*\n\s*<<: \*common-variables\s*\n\s*HTTP_PORT: 3000\s*\n\s*JAEGER_BASE_URL:)'
    api_env_replacement = r'\1\n      HOMER_BASE_URL: '\''http://homer:9080'\''\n      HOMER_USERNAME: '\''admin'\''\n      HOMER_PASSWORD: '\''admin123'\'''
    content = re.sub(api_env_pattern, api_env_replacement, content, flags=re.MULTILINE)
    
    # Also add homer to depends_on
    if 'homer:' not in content.split('api-server:')[1].split('depends_on:')[1].split('networks:')[0]:
        depends_pattern = r'(api-server:.*?depends_on:\s*\n\s*mysql:.*?\n\s*redis:.*?\n\s*jaeger:.*?\n)'
        depends_replacement = r'\1      homer:\n        condition: service_started\n'
        content = re.sub(depends_pattern, depends_replacement, content, flags=re.DOTALL)

with open('docker-compose.yaml', 'w') as f:
    f.write(content)

print("✅ Added Homer services to docker-compose.yaml")
PYTHON_SCRIPT

if [ $? -ne 0 ]; then
  echo "⚠️  Python script failed, trying manual approach..."
  
  # Manual approach - append services
  cat >> docker-compose.yaml << 'EOF'

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

  heplify-server:
    image: sipcapture/heplify-server:latest
    restart: always
    ports:
      - "9060:9060/udp"
      - "3050:3050"
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
EOF

  # Manually update api-server
  sed -i.bak2 '/api-server:/,/ipv4_address: 172.10.0.30/ {
    /HTTP_PORT: 3000/a\
      HOMER_BASE_URL: '\''http://homer:9080'\''\
      HOMER_USERNAME: '\''admin'\''\
      HOMER_PASSWORD: '\''admin123'\''
  }' docker-compose.yaml

  echo "✅ Added Homer services (manual method)"
fi

echo ""
echo "2. Creating Homer database..."
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer;" 2>/dev/null || echo "⚠️  Database may already exist"

echo ""
echo "3. Starting Homer services..."
sudo docker compose up -d homer heplify-server

echo ""
echo "4. Updating API server configuration..."
sudo docker compose restart api-server

echo ""
echo "=========================================="
echo "✅ Homer Setup Complete"
echo "=========================================="
echo ""
echo "Homer Web UI: http://localhost:9080"
echo "  Default credentials: admin / admin123"
echo ""
echo "Next steps:"
echo "  1. Wait for services to start: sudo docker compose ps"
echo "  2. Check logs: sudo docker compose logs homer"
echo "  3. Test PCAP download in webapp"
echo ""

