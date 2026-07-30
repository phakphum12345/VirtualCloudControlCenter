# Anti-theft mode

## Implemented

- Owner-configured opt-in switch
- Six-to-twelve digit owner PIN protected with salted PBKDF2-HMAC-SHA256
  (210,000 iterations), including verification compatibility for the previous
  salted SHA-256 format
- Configurable failed-attempt threshold from 1 to 10
- Requested clip duration from 30 to 180 seconds
- Wi-Fi-only upload preference
- Persistent local settings and activity logging
- Testable failed-attempt state machine
- Foreground camera capture on Android and iOS with system permission and camera
  indicator
- Time-limited, no-audio recording with a visible in-app preview
- Chunked AES-256-GCM encryption with a key stored in platform secure storage
- Source-video deletion after successful encryption
- Evidence metadata for time, network state, and device summary
- Configurable retention by age and maximum clip count
- Owner-authorized Google Drive `drive.file` upload of encrypted evidence
- Offline/Wi-Fi-aware queue retries when the app starts or the owner retries
- Evidence history with export, retry-upload, and confirmed local deletion

## Safety boundaries

- The application does not block the operating-system power button, screen
  lock, emergency calling, or shutdown controls.
- Camera recording must use native platform permission and a visible operating
  system indicator.
- A failed PIN event does not claim that a video exists until the native camera
  adapter confirms recording and output finalization.
- Google Drive cannot be selected until the owner completes OAuth, selects a
  destination folder, and explicitly enables upload.
- Offline files remain local and encrypted until an authorized destination
  becomes available. The app never stores Google access tokens itself.

## Platform limits

- Recording starts only while this application is visible. It is not a hidden
  background camera and does not bypass the Android or iOS camera indicator.
- Android and iOS can suspend or stop the application; recording is not
  guaranteed after force-stop, shutdown, or operating-system suspension.
- iOS does not permit this application to start a camera secretly in the
  background or act as an operating-system lock screen.
- Google Drive requires a correctly configured OAuth client for the application
  package/bundle and an explicit owner sign-in.
- Queue retry is app-lifecycle based. A future server-backed release may add
  durable owner notifications and background transfer without weakening OAuth.

## Google Drive setup

The current Google Cloud project number derived from the owner-provided Web
OAuth client is `667656026445`. The client ID is injected at build time through
the `GOOGLE_SERVER_CLIENT_ID` GitHub Actions secret and is not committed to
source.

For Android, create or verify an Android OAuth client in the same Cloud project:

- Package name: `com.phakphum.aiassistant`
- Debug SHA-1:
  `3A:B5:E7:F2:63:FA:54:DD:52:6A:F6:1C:E2:19:1A:24:B9:E1:7C:58`
- Enable Google Drive API
- Configure the OAuth consent screen and add test users while the app remains
  in testing

Production builds must use the SHA-1 of the production upload/app-signing key,
not the debug fingerprint above.
