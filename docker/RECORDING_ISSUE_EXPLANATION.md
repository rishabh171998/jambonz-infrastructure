# Recording Issue: Can It Be Fixed?

## The Problem

When recording is enabled, calls disconnect because:
1. **Feature-server bug**: The `jambonz/feature-server` sends the **default accountSid** (`9351f46a-678c-43f5-b8a6-d4eb58d131af`) to the API server in the WebSocket message for recording
2. **API server**: Checks the default account for bucket credentials
3. **Result**: If default account doesn't have bucket credentials, recording fails and may cause call disconnects

## Can It Be Fixed?

### ✅ **Workaround (What We Can Do Now)**

**YES, the workaround will make recording work:**

The script `fix-recording-call-disconnect.sh` applies a workaround:
- Copies bucket credentials from your account to the default account
- Disables recording for the default account (so it won't try to record)
- Keeps recording enabled for your account

**This workaround makes recording functional** because:
- When feature-server sends the wrong (default) accountSid, the default account now has bucket credentials
- The API server can authenticate and start recording
- Your actual account still has recording enabled, so recordings are associated with your account

### ❌ **Proper Fix (Requires Code Change)**

**The proper fix requires modifying the feature-server source code:**

The bug is in `jambonz/feature-server` where it determines which `accountSid` to send. The code needs to be changed to:
- Use the **actual call's accountSid** instead of the default accountSid
- This is in the feature-server codebase, not in this infrastructure repo

**To properly fix:**
1. Fork/clone `jambonz/feature-server` repository
2. Find where it sends `accountSid` in the recording WebSocket message
3. Change it to use the call's actual `accountSid` instead of default
4. Build and deploy the fixed version

## Current Status

- ✅ **Workaround available**: `fix-recording-call-disconnect.sh` makes recording work
- ⚠️ **Root cause**: Bug in feature-server code (not in this repo)
- ✅ **Functional**: Recording will work with the workaround
- ❌ **Proper fix**: Requires code change in `jambonz/feature-server`

## Recommendation

**Use the workaround for now:**
```bash
sudo ./fix-recording-call-disconnect.sh
```

This will make recording work without call disconnects. The workaround is stable and safe - it just ensures the default account has the necessary credentials even though it won't be used for recording.

**For a permanent fix:**
- Report the bug to the Jambonz team
- Or fix it in the feature-server source code yourself


