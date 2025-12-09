# Recording Bug - Code Location Analysis

## CallSession Code Analysis

Based on the `CallSession` class code provided, here's where the bug likely is:

### Where Recording is Initiated

**File:** `lib/call-session.js` (or similar)

**Location:** Lines 1000-1008 in `_notifyCallStatusChange` method

```javascript
if (callStatus === CallStatus.InProgress) {
  if (this.accountInfo.account.record_all_calls ||
    this.application.record_all_calls) {
    this.backgroundTaskManager.newTask('record');
  }
}
```

### Available Account SID

**Location:** Line 500 - `accountSid` getter

```javascript
get accountSid() {
  return this.callInfo.accountSid;
}
```

✅ **The CallSession has the correct `accountSid` available via `this.accountSid`**

### Where the Bug Likely Is

The bug is **NOT** in `CallSession`. The bug is in one of these locations:

#### 1. BackgroundTaskManager.newTask('record')

**File:** `lib/utils/background-task-manager.js` (or similar)

**Issue:** When creating the 'record' task, it might not be passing `this.cs.accountSid` to the task.

**Expected:**
```javascript
async newTask(type, opts) {
  if (type === 'record') {
    const task = new RecordTask({
      cs: this.cs,
      accountSid: this.cs.accountSid,  // ✅ Should use call session's accountSid
      ...
    });
  }
}
```

**Actual (likely):**
```javascript
async newTask(type, opts) {
  if (type === 'record') {
    const task = new RecordTask({
      cs: this.cs,
      accountSid: this.cs.application?.account_sid || defaultAccountSid,  // ❌ Wrong
      ...
    });
  }
}
```

#### 2. Record Task WebSocket Message Construction

**File:** `lib/tasks/record-task.js` or `lib/tasks/background-record.js` (or similar)

**Issue:** When constructing the WebSocket message to send to API server, it's using the wrong accountSid.

**Expected:**
```javascript
_initRecord() {
  const payload = {
    accountSid: this.cs.accountSid,  // ✅ Use call session's accountSid
    callSid: this.cs.callSid,
    ...
  };
  this.ws.send(JSON.stringify(payload));
}
```

**Actual (likely):**
```javascript
_initRecord() {
  const payload = {
    accountSid: this.cs.application?.account_sid || 
                this.cs.accountInfo?.service_provider?.default_account_sid || 
                DEFAULT_ACCOUNT_SID,  // ❌ Wrong - using default
    callSid: this.cs.callSid,
    ...
  };
  this.ws.send(JSON.stringify(payload));
}
```

### How to Find the Exact Bug

1. **Search for `_initRecord` function:**
   ```bash
   grep -r "_initRecord" jambonz-feature-server/
   ```

2. **Search for record task creation:**
   ```bash
   grep -r "newTask.*record\|new RecordTask" jambonz-feature-server/
   ```

3. **Search for WebSocket message with accountSid:**
   ```bash
   grep -r "accountSid.*ws\|websocket.*accountSid" jambonz-feature-server/
   ```

### The Fix

The fix should be in the record task initialization or WebSocket message construction:

**Change from:**
```javascript
accountSid: this.cs.application?.account_sid || defaultAccountSid
```

**To:**
```javascript
accountSid: this.cs.accountSid
```

### Verification

After the fix, verify that:
1. `this.cs.accountSid` returns the correct account (e.g., `bed525b4-af09-40d2-9fe7-cdf6ae577c69`)
2. The WebSocket message payload includes this correct `accountSid`
3. API server receives the correct `accountSid` and checks the right account's bucket credentials

