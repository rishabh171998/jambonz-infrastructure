#!/bin/bash
# Check heplify-server logs to see why it's restarting

cd "$(dirname "$0")"

echo "Checking heplify-server logs..."
echo "=========================================="
sudo docker compose logs heplify-server --tail 50

