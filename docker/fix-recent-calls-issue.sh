#!/bin/bash
# Fix recent calls page issue - handles API response format mismatch

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Recent Calls Page Issue"
echo "=========================================="
echo ""

# Check if webapp source exists
WEBAPP_SRC="jambonz-webapp-main/src"
if [ ! -d "$WEBAPP_SRC" ]; then
  echo "❌ Webapp source not found at: $WEBAPP_SRC"
  echo "   This fix requires the webapp source code"
  exit 1
fi

echo "1. Checking current API response format..."
echo "-------------------------------------------"

# Get account SID from database
ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  echo "⚠️  Could not get account SID from database"
  echo "   Will proceed with fix anyway"
else
  echo "   Testing with account: $ACCOUNT_SID"
  
  # Test API response
  HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}
  API_RESPONSE=$(curl -s -H "Authorization: Bearer $(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "")
  
  if echo "$API_RESPONSE" | grep -q "page_size"; then
    echo "   ✅ API returns 'page_size' field"
  fi
  
  if echo "$API_RESPONSE" | grep -q "batch"; then
    echo "   ✅ API returns 'batch' field"
  fi
  
  if echo "$API_RESPONSE" | grep -q '"data"'; then
    echo "   ✅ API returns 'data' field"
  else
    echo "   ⚠️  API response missing 'data' field"
  fi
fi
echo ""

echo "2. Fixing webapp to handle API response properly..."
echo "-------------------------------------------"

# Fix the recent-calls component to handle both response formats
RECENT_CALLS_FILE="$WEBAPP_SRC/containers/internal/views/recent-calls/index.tsx"

if [ -f "$RECENT_CALLS_FILE" ]; then
  # Create backup
  cp "$RECENT_CALLS_FILE" "${RECENT_CALLS_FILE}.backup"
  echo "   ✅ Created backup: ${RECENT_CALLS_FILE}.backup"
  
  # Fix the response handling to be more robust
  sed -i.bak2 's/getRecentCalls(accountSid, payload)/getRecentCalls(accountSid, payload)/' "$RECENT_CALLS_FILE"
  
  # Update the response handling to check for data existence
  cat > /tmp/fix_recent_calls.js << 'EOF'
const fs = require('fs');
const file = process.argv[1];
let content = fs.readFileSync(file, 'utf8');

// Fix the response handling to be more defensive
const oldPattern = /getRecentCalls\(accountSid, payload\)\s*\.then\(\(\{ json \}\) => \{[\s\S]*?setCalls\(json\.data\);[\s\S]*?setCallsTotal\(json\.total\);[\s\S]*?setMaxPageNumber\(Math\.ceil\(json\.total \/ Number\(perPageFilter\)\)\);[\s\S]*?\}\)/;

const newCode = `getRecentCalls(accountSid, payload)
      .then(({ json }) => {
        // Handle both 'page_size' and 'batch' field names
        const batchSize = json.batch || json.page_size || Number(perPageFilter);
        const pageNum = typeof json.page === 'string' ? Number(json.page) : json.page || 1;
        
        // Ensure data exists and is an array
        if (json && json.data && Array.isArray(json.data)) {
          setCalls(json.data);
          setCallsTotal(json.total || 0);
          setMaxPageNumber(Math.ceil((json.total || 0) / Number(perPageFilter)));
        } else {
          console.warn('Invalid API response format:', json);
          setCalls([]);
          setCallsTotal(0);
          setMaxPageNumber(1);
        }
      })`;

if (oldPattern.test(content)) {
  content = content.replace(oldPattern, newCode);
  fs.writeFileSync(file, content, 'utf8');
  console.log('Fixed response handling');
} else {
  console.log('Pattern not found, trying alternative fix...');
  
  // Alternative: Just make the data check more defensive
  const altPattern = /setCalls\(json\.data\);/;
  if (altPattern.test(content)) {
    content = content.replace(
      /setCalls\(json\.data\);/,
      `// Handle API response format variations
        if (json && json.data && Array.isArray(json.data)) {
          setCalls(json.data);
        } else {
          console.warn('Invalid API response:', json);
          setCalls([]);
        }`
    );
    fs.writeFileSync(file, content, 'utf8');
    console.log('Applied defensive data check');
  } else {
    console.log('Could not find exact pattern to replace');
    console.log('Manual fix may be required');
  }
}
EOF

  # Apply the fix using Node.js if available, otherwise use sed
  if command -v node &> /dev/null; then
    node /tmp/fix_recent_calls.js "$RECENT_CALLS_FILE" 2>/dev/null || {
      echo "   ⚠️  Node.js fix failed, trying sed-based fix..."
      
      # Simpler sed-based fix
      sed -i.bak3 's/setCalls(json\.data);/if (json \&\& json.data \&\& Array.isArray(json.data)) { setCalls(json.data); } else { console.warn("Invalid API response:", json); setCalls([]); }/' "$RECENT_CALLS_FILE" 2>/dev/null || true
    }
  else
    # Fallback to sed
    echo "   Using sed-based fix (Node.js not available)..."
    sed -i.bak3 's/setCalls(json\.data);/if (json \&\& json.data \&\& Array.isArray(json.data)) { setCalls(json.data); } else { console.warn("Invalid API response:", json); setCalls([]); }/' "$RECENT_CALLS_FILE" 2>/dev/null || true
  fi
  
  echo "   ✅ Updated recent-calls component"
else
  echo "   ❌ Recent calls component not found: $RECENT_CALLS_FILE"
fi
echo ""

echo "3. Rebuilding webapp..."
echo "-------------------------------------------"
if [ -f "docker-compose.yaml" ] || [ -f "docker-compose.yml" ]; then
  echo "   Rebuilding webapp container..."
  sudo docker compose build webapp
  echo "   ✅ Webapp rebuilt"
  
  echo ""
  echo "   Restarting webapp..."
  sudo docker compose restart webapp
  echo "   ✅ Webapp restarted"
else
  echo "   ⚠️  docker-compose.yaml not found"
  echo "   You may need to rebuild manually:"
  echo "     sudo docker compose build webapp"
  echo "     sudo docker compose restart webapp"
fi
echo ""

echo "=========================================="
echo "Fix Complete"
echo "=========================================="
echo ""
echo "The recent calls page should now:"
echo "  1. Handle both 'page_size' and 'batch' response fields"
echo "  2. Check that 'data' exists before using it"
echo "  3. Show empty state instead of crashing if API response is invalid"
echo ""
echo "If the issue persists:"
echo "  1. Check browser console for errors"
echo "  2. Verify API is returning data: curl http://localhost:3000/v1/Accounts/YOUR_ACCOUNT_SID/RecentCalls"
echo "  3. Check webapp logs: sudo docker compose logs webapp"
echo ""

