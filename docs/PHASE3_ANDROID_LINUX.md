# Phase 3: Android and Linux

## Android foundation implemented

- Native method channel: `com.phakphum.aiassistant/android`
- Memory, storage, battery, and processor diagnostics
- Allowlisted Wi-Fi, Bluetooth, display, storage, battery, notification, and
  sound Settings intents
- Full-display H.264 MP4 recording through MediaProjection after the system
  permission prompt
- Visible foreground-service notification throughout capture
- Pause, resume, stop, and app-scoped Movies output
- Native readiness checks: start and lifecycle controls return success only
  after the recorder confirms the requested state
- Honest rejection of microphone and system audio until those capture paths are
  implemented

## Android next

- Device/emulator integration tests for permission denial, encoder failure,
  rotation, and process interruption
- Microphone capture after runtime permission
- Playback capture for system audio on supported Android versions
- MediaStore export and recording history

## Linux foundation implemented

- Native method channel: `com.phakphum.aiassistant/linux`
- Procfs memory, filesystem storage, and processor diagnostics
- Allowlisted GNOME Settings panels launched without shell evaluation

## Linux next

- XDG Desktop Portal permission discovery and PipeWire screen-capture lifecycle
- Desktop-specific D-Bus adapters beyond GNOME
- Battery and network diagnostics

No Android accessibility service is enabled or requested.
