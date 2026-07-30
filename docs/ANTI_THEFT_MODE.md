# Anti-theft mode

## Implemented foundation

- Owner-configured opt-in switch
- Six-to-twelve digit owner PIN stored as a salted SHA-256 hash
- Configurable failed-attempt threshold from 1 to 10
- Requested clip duration from 30 to 180 seconds
- Wi-Fi-only upload preference
- Persistent local settings and activity logging
- Testable failed-attempt state machine

## Safety boundaries

- The application does not block the operating-system power button, screen
  lock, emergency calling, or shutdown controls.
- Camera recording must use native platform permission and a visible operating
  system indicator.
- A failed PIN event does not claim that a video exists until the native camera
  adapter confirms recording and output finalization.
- Google Drive cannot be selected until the owner completes OAuth, selects a
  destination folder, and explicitly enables upload.
- Offline files must remain local and encrypted until an authorized destination
  becomes available.

## Remaining native work

- Android visible camera foreground service and lifecycle verification
- iOS camera flow within Apple's foreground and permission restrictions
- Desktop camera adapters where supported
- Encrypted local media storage and retention controls
- Google OAuth, folder selection, resumable upload, and verified upload result
