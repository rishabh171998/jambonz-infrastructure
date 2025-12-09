# Recording Audio Bug - Summary

## The Problem
When recording is enabled, calls have **no audio**. When recording is disabled, audio works fine.

## Root Cause
**Bug in jambonz/feature-server**: The `_initRecord` function sends the **wrong `account_sid`** to the API server in the recording WebSocket message.

### Evidence

**Feature-server logs (correct account):**
```json
{
  "accountSid": "bed525b4-af09-40d2-9fe7-cdf6ae577c69",  // ✅ Correct
  "callSid": "1df5a76b-3334-4edf-b38d-d47deb82a9bf",
  "msg": "initiating Background task record"
}
```

**API server logs (wrong account received):**
```json
{
  "obj": {
    "accountSid": "9351f46a-678c-43f5-b8a6-d4eb58d131af",  // ❌ Wrong - default account
    "callSid": "1df5a76b-3334-4edf-b38d-d47deb82a9bf",
    ...
  },
  "msg": "received JSON message from jambonz"
}
```

**API server closes WebSocket:**
```
"account 9351f46a-678c-43f5-b8a6-d4eb58d131af does not have any bucket credential, close the socket"
```

**Result:**
- Recording task fails
- Main audio listen task is killed
- **No audio in calls**

## Where the Bug Is

The bug is in **jambonz/feature-server** in one of these locations:

### Location 1: BackgroundTaskManager.newTask('record')
**File:** `lib/utils/background-task-manager.js`

When creating the record task, it might not be passing the correct `accountSid`:
```javascript
// ❌ WRONG (likely current code):
accountSid: this.cs.application?.account_sid || defaultAccountSid

// ✅ CORRECT (should be):
accountSid: this.cs.accountSid  // From call session
```

### Location 2: Record Task WebSocket Message
**File:** `lib/tasks/record-task.js` or `lib/tasks/background-record.js`

In the `_initRecord` function, when constructing the WebSocket message:
```javascript
// ❌ WRONG (likely current code):
accountSid: this.cs.application?.account_sid || defaultAccountSid

// ✅ CORRECT (should be):
accountSid: this.cs.accountSid  // From call session
```

**Note:** The `CallSession` class correctly has `this.accountSid` available (returns `this.callInfo.accountSid`), so the bug is in how the record task accesses it.

## Why This Happens

Looking at the initial webhook logs, feature-server receives:
```json
{
  "accountSid": "9351f46a-678c-43f5-b8a6-d4eb58d131af",  // Default account
  "applicationSid": "08d78564-d3f6-4db4-95ce-513ae757c2c9"
}
```

But then later it correctly identifies:
```json
{
  "accountSid": "bed525b4-af09-40d2-9fe7-cdf6ae577c69"  // Your account
}
```

The issue is that when building the recording WebSocket message, it's using the account_sid from the initial webhook (default account) instead of the call session's account_sid.

## The Fix Needed

In **jambonz/feature-server**, the `_initRecord` function needs to:
1. Use `this.accountSid` from the call session (not from initial webhook)
2. Ensure the WebSocket message payload includes the correct `account_sid`

## Workarounds

### ❌ WRONG: Copy bucket credentials to default account
This masks the bug and is not a proper solution.

### ✅ CORRECT: Disable recording until bug is fixed
```bash
cd /opt/jambonz-infrastructure/docker
sudo ./disable-recording-until-fixed.sh
```

## Reporting the Bug

**Repository:** https://github.com/jambonz/jambonz-feature-server

**Issue Title:** Feature-server sends wrong account_sid to API server in recording WebSocket message

**Description:**
When `record_all_calls` is enabled, feature-server sends the wrong `account_sid` to the API server in the recording WebSocket message. It uses the default account (`9351f46a-678c-43f5-b8a6-d4eb58d131af`) instead of the actual call's account_sid.

**Location:** 
- `lib/utils/background-task-manager.js` - `newTask('record')` method
- OR `lib/tasks/record-task.js` / `lib/tasks/background-record.js` - `_initRecord()` method

**Expected:** Use `this.cs.accountSid` or `callSession.accountSid` from the call session
**Actual:** Uses `this.cs.application?.account_sid` or default account instead of `this.cs.accountSid`

**Impact:** 
- Recording fails
- Main audio stream is killed
- No audio in calls when recording is enabled

