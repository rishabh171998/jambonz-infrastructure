#!/bin/bash
# Simple fix for recent calls - update the component to handle API response properly

set -e

cd "$(dirname "$0")"

WEBAPP_SRC="jambonz-webapp-main/src/containers/internal/views/recent-calls/index.tsx"

if [ ! -f "$WEBAPP_SRC" ]; then
  echo "❌ Webapp source not found: $WEBAPP_SRC"
  exit 1
fi

echo "Fixing recent calls component..."

# Create backup
cp "$WEBAPP_SRC" "${WEBAPP_SRC}.backup.$(date +%Y%m%d_%H%M%S)"

# Fix: Make the response handling more defensive
# Replace the getRecentCalls promise handler to check for data existence

# Read the file
CONTENT=$(cat "$WEBAPP_SRC")

# Check if fix already applied
if echo "$CONTENT" | grep -q "if (json && json.data && Array.isArray(json.data))"; then
  echo "✅ Fix already applied"
  exit 0
fi

# Apply fix: Replace the setCalls line with defensive check
NEW_CONTENT=$(echo "$CONTENT" | sed 's/setCalls(json\.data);/if (json \&\& json.data \&\& Array.isArray(json.data)) {\n          setCalls(json.data);\n        } else {\n          console.warn("Invalid API response format:", json);\n          setCalls([]);\n        }/')

# Write back
echo "$NEW_CONTENT" > "$WEBAPP_SRC"

echo "✅ Fixed recent calls component"
echo ""
echo "Now rebuild the webapp:"
echo "  sudo docker compose build webapp"
echo "  sudo docker compose restart webapp"

