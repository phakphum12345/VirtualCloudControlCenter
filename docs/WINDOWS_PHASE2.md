# Windows Phase 2

The Windows adapter uses a typed Flutter method channel:

```text
com.phakphum.aiassistant/windows
```

## Implemented and verified by native return values

- Windows memory, disk, logical-processor, and process information
- Installed/running process inspection ordered by working-set memory
- Confirmed process termination by PID
- Allowlisted application launching
- Allowlisted Windows Settings URI launching
- Default output volume control from 0 to 100 percent
- Large-file discovery in Downloads, skipping inaccessible folders
- Visible full-desktop screenshots saved under Pictures/Phakphum AI
- Visible full-display H.264 MP4 recording saved under Videos/Phakphum AI
- Recording countdown, pause, resume, stop, output path, and session history
- Emergency Stop terminates an active native recording

## Current recording boundary

The current recorder captures the Windows virtual desktop through a GDI frame
source and encodes it through Windows Media Foundation. Microphone audio, system
audio, and selected-window capture remain unavailable. When either audio option
is requested, the native adapter returns failure and does not start recording.
Successful stop is reported only after the MP4 sink writer finalizes the file.

## Native safety boundaries

- Settings URIs are selected from a fixed allowlist.
- Application launch targets are selected from a fixed allowlist.
- No AI-generated PowerShell or shell commands are executed.
- Process termination rejects system PID values and the assistant process.
- Dart permission policy requires confirmation before capture, volume changes,
  and process termination.
