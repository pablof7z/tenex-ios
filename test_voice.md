# Voice Input Testing Instructions

## What was fixed:

1. **Added comprehensive error logging** to AudioManager with [AudioManager] prefix for all operations
2. **Fixed silent failures** - errors are now properly logged and exposed via @Published properties
3. **Added permission checking** before attempting to record
4. **Added user-visible error messages** in the UI
5. **Set explicit locale** for speech recognizer (en-US)
6. **Added error state handling** with alerts for permission issues

## How to test:

1. Open the TENEX app in the simulator
2. Navigate to a conversation
3. Try the voice call feature (phone icon)
4. Watch for any error messages in the UI
5. Check Xcode console for detailed [AudioManager] logs

## Expected logs when voice input fails:

```
[AudioManager] Initialized
[AudioManager] Speech recognizer locale: en-US
[AudioManager] Speech recognizer available: false/true
[AudioManager] Requesting permissions...
[AudioManager] Microphone permission: true/false
[AudioManager] Speech recognition authorization status: 0-3
[AudioManager] Starting recording...
[AudioManager] ERROR: <specific error message>
```

## Common issues and their logs:

1. **Voice Services Asset Error** (your original error):
   - This is an iOS system error when voice recognition assets aren't downloaded
   - Our code now handles this gracefully with "Speech recognition is not available" message

2. **Permission Denied**:
   - Shows alert with "Open Settings" button
   - Logs show permission status

3. **Speech Recognizer Unavailable**:
   - Could be network issues or language settings
   - Error message shown to user

## To view console logs in Xcode:

1. Run the app from Xcode
2. Look at the console output at the bottom
3. Filter by "[AudioManager]" to see voice-related logs