#!/bin/bash
# Update all Jambonz Docker images to latest versions

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Update Jambonz Docker Images"
echo "=========================================="
echo ""

echo "This will pull the latest images for all Jambonz services."
echo "Note: This may take several minutes depending on your internet speed."
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo "Pulling latest images..."
echo ""

# List of Jambonz images to update
IMAGES=(
  "jambonz/api-server:latest"
  "jambonz/feature-server:latest"
  "jambonz/sbc-inbound:latest"
  "jambonz/sbc-outbound:latest"
  "jambonz/sbc-call-router:latest"
  "jambonz/sbc-registrar:latest"
  "drachtio/drachtio-server:latest"
  "drachtio/drachtio-freeswitch-mrf:latest"
  "drachtio/rtpengine:jambonz-test"
)

for IMAGE in "${IMAGES[@]}"; do
  echo "Pulling $IMAGE..."
  docker pull "$IMAGE" || sudo docker pull "$IMAGE"
  echo ""
done

echo "=========================================="
echo "Images Updated"
echo "=========================================="
echo ""
echo "To apply the updates, restart services:"
echo "  sudo docker compose restart"
echo ""
echo "Or restart specific services:"
echo "  sudo docker compose restart sbc-inbound api-server feature-server"
echo ""
echo "Note: Restarting will cause brief service interruption."
echo ""

