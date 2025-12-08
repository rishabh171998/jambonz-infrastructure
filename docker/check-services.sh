#!/bin/bash
# Quick script to check all services status

cd /opt/jambonz-infrastructure/docker

echo "=== Service Status ==="
sudo docker compose ps

echo ""
echo "=== Service Health Checks ==="

echo ""
echo "MySQL:"
if sudo docker compose exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; then
    echo "✓ MySQL is healthy"
else
    echo "✗ MySQL is not responding"
fi

echo ""
echo "Redis:"
if sudo docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "✓ Redis is responding"
else
    echo "✗ Redis is not responding"
fi

echo ""
echo "InfluxDB:"
if sudo docker compose exec -T influxdb influx -execute "SHOW DATABASES" 2>/dev/null | grep -q jambones; then
    echo "✓ InfluxDB jambones database exists"
else
    echo "✗ InfluxDB database not found"
fi

echo ""
echo "Jaeger:"
if curl -s http://localhost:16686 > /dev/null 2>&1; then
    echo "✓ Jaeger UI is accessible"
    echo "  Access at: http://\${HOST_IP}:16686"
else
    echo "✗ Jaeger UI is not accessible"
fi

echo ""
echo "API Server:"
if sudo docker compose logs api-server --tail 5 2>/dev/null | grep -q "listening\|started"; then
    echo "✓ API Server appears to be running"
else
    echo "✗ API Server may not be ready"
fi

echo ""
echo "sbc-inbound:"
if sudo docker compose logs sbc-inbound --tail 5 2>/dev/null | grep -q "listening\|connected"; then
    echo "✓ sbc-inbound appears to be running"
else
    echo "✗ sbc-inbound may not be ready"
fi

echo ""
echo "=== Recent Logs (last 3 lines each) ==="
echo ""
echo "API Server:"
sudo docker compose logs api-server --tail 3 2>/dev/null || echo "No logs available"

echo ""
echo "sbc-inbound:"
sudo docker compose logs sbc-inbound --tail 3 2>/dev/null || echo "No logs available"

echo ""
echo "feature-server:"
sudo docker compose logs feature-server --tail 3 2>/dev/null || echo "No logs available"

