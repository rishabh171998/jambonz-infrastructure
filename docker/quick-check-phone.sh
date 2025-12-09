#!/bin/bash
# Quick check if phone number has application - simple version

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

echo "Checking phone number: 08064061518"
echo ""

$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE number LIKE '%8064061518%' OR number LIKE '%08064061518%';" 2>/dev/null

echo ""
echo "If application_sid is NULL, assign an application in webapp!"

