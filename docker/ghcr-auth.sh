#!/bin/bash
# Script to authenticate with GitHub Container Registry (GHCR)
# Usage: ./ghcr-auth.sh

set -e

# Check if credentials are provided via environment variables
if [ -z "$GHCR_USER" ] || [ -z "$GHCR_PAT" ]; then
  echo "Error: GHCR_USER and GHCR_PAT environment variables must be set"
  echo "Usage: export GHCR_USER=your-username && export GHCR_PAT=your-pat && ./ghcr-auth.sh"
  exit 1
fi

echo "Authenticating with GitHub Container Registry..."
echo "$GHCR_PAT" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

if [ $? -eq 0 ]; then
  echo "Successfully authenticated with GHCR!"
  echo "You can now pull images from ghcr.io"
else
  echo "Failed to authenticate with GHCR"
  exit 1
fi

