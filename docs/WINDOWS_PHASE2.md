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

## Intentionally unavailable

Screen recording remains unavailable until a Windows Graphics Capture pipeline
with explicit source selection, visible recording state, microphone/system-audio
handling, and verified output-file finalization is implemented. The application
does not claim that recording succeeded.

## Native safety boundaries

- Settings URIs are selected from a fixed allowlist.
- Application launch targets are selected from a fixed allowlist.
- No AI-generated PowerShell or shell commands are executed.
- Process termination rejects system PID values and the assistant process.
- Dart permission policy requires confirmation before capture, volume changes,
  and process termination.
