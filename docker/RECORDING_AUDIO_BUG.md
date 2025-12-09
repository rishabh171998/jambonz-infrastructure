# Recording Audio Bug - Root Cause Analysis

## Problem
When recording is enabled, calls have no audio. When recording is disabled, audio works fine.

## Root Cause
**Bug in jambonz/feature-server**: When sending the recording WebSocket message to the API server, feature-server sends the **wrong account_sid**.

### Evidence from Logs

1. **Feature-server correctly identifies the account:**
   ```
   feature-server-1 | {"accountSid":"bed525b4-af09-40d2-9fe7-cdf6ae577c69",...}
   ```

2. **But API server receives wrong account_sid:**
   ```
   api-server-1 | {"obj":{...,"accountSid":"9351f46a-678c-43f5-b8a6-d4eb58d131af",...}}
   ```
   (This is the default account, not the actual call account)

3. **API server closes WebSocket:**
   ```
   api-server-1 | "account 9351f46a-678c-43f5-b8a6-d4eb58d131af does not have any bucket credential, close the socket"
   ```

4. **Recording task fails and kills main audio:**
   ```
   feature-server-1 | "TaskListen:kill closing websocket"
   feature-server-1 | "listen is being killed"
   ```

## Why This Happens

The bug is in the `_initRecord` function in jambonz/feature-server. When constructing the WebSocket message payload to send to the API server, it's using the wrong account_sid. 

Possible causes:
- Using `service_provider_sid` default account instead of call's `account_sid`
- Using application's associated account instead of call's account
- Bug in how the account_sid is retrieved from the call session

## Impact

- **No audio in calls** when recording is enabled
- **Recording fails** because API server checks wrong account
- **Main audio stream is killed** when recording task fails

## Workarounds (NOT RECOMMENDED)

1. ❌ Copy bucket credentials to default account - **This is wrong** and masks the bug
2. ✅ Disable recording until bug is fixed - **This is the only safe option**

## Proper Fix

This requires a code fix in **jambonz/feature-server**. The `_initRecord` function needs to be updated to use the correct `account_sid` from the call session when sending the WebSocket message to the API server.

### Where to Report
- GitHub: https://github.com/jambonz/jambonz-feature-server
- Issue: Feature-server sends wrong account_sid to API server in recording WebSocket message

### Expected Fix
The WebSocket message should use:
```javascript
accountSid: callSession.accountSid  // From the actual call
```

Instead of:
```javascript
accountSid: defaultAccountSid  // Wrong - from service provider or default
```

## Current Status

- ✅ Bug identified and documented
- ❌ No code fix available yet
- ✅ Workaround: Disable recording (`record_all_calls = 0`)

## Test Case

1. Enable recording for account `bed525b4-af09-40d2-9fe7-cdf6ae577c69`
2. Make a call
3. Check API server logs - should see `accountSid: "bed525b4-af09-40d2-9fe7-cdf6ae577c69"`
4. Currently sees: `accountSid: "9351f46a-678c-43f5-b8a6-d4eb58d131af"` ❌

