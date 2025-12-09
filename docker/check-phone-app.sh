#!/bin/bash
# Quick check if phone number has application

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "Checking phone number: 08064061518"
echo ""

# Check if phone number has application
PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE number LIKE '%8064061518%' OR number LIKE '%08064061518%';" 2>/dev/null | grep -v "number" || echo "")

if [ -z "$PHONE_INFO" ]; then
  echo "❌ Phone number not found in database"
else
  echo "$PHONE_INFO"
  APP_SID=$(echo "$PHONE_INFO" | awk '{print $2}')
  
  if [ -z "$APP_SID" ] || [ "$APP_SID" = "NULL" ]; then
    echo ""
    echo "❌ PROBLEM: Phone number has NO application assigned"
    echo ""
    echo "FIX: In webapp → Phone Numbers → Edit 08064061518"
    echo "     Assign an Application"
  else
    echo ""
    echo "✅ Phone number has application: $APP_SID"
  fi
fi

echo ""

