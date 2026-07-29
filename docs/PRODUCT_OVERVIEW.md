# Phakphum AI System Assistant — Product Overview

A cross-platform AI assistant for screen recording, application management, file management, system settings, diagnostics, and safe device automation.

## Application information

- **Name:** Phakphum AI System Assistant
- **Application ID:** `com.phakphum.aiassistant`
- **Main framework:** Flutter
- **Primary language:** Dart
- **Native adapters:** C++, C#, Swift, Kotlin, JavaScript, D-Bus and platform APIs as required

## Supported platforms

| Platform | Screen recording | App control | File management | System settings |
|---|---:|---:|---:|---:|
| Windows | Full | Full | Full | Extensive |
| macOS | Full | Partial | Full | Partial |
| Linux | Full | Partial | Full | Desktop dependent |
| Android | Full | Limited | Scoped | Limited |
| iOS / iPadOS | Restricted | Restricted | Scoped | Restricted |
| Web / ChromeOS | Browser capture | Browser only | User-selected files | Not available |

> The assistant must report the real capabilities of the current device. It must never claim that an unsupported action succeeded.

## Main modules

### AI Command Center

Accepts Thai or English text and voice commands, converts them into structured actions, checks permissions, classifies risk, asks for confirmation when needed, and reports the actual result.

Example commands:

```text
เริ่มบันทึกหน้าจอพร้อมเสียงไมโครโฟน
เปิด Visual Studio Code
เปิดโฟลเดอร์โปรเจกต์ Flutter
ลดเสียงเหลือ 30%
หาไฟล์ขนาดใหญ่ใน Downloads
แสดงโปรแกรมที่ใช้ RAM มากที่สุด
หยุดอัดหน้าจอและบันทึกชื่อ Flutter Tutorial
```

### Screen Recorder

- Full-display recording
- Window recording where supported
- Microphone audio
- System audio where supported
- Pause and resume
- Screenshots
- Countdown
- Resolution and FPS selection
- Visible recording status
- Recording history
- Output folder shortcut

### Application Manager

- Find installed applications
- Open applications
- Close or restart applications after confirmation
- Detect unresponsive applications
- Show CPU and memory usage
- Open application folders and settings

### File Manager

- Search, create, rename, copy, and move files
- Find large and duplicate files
- Create and extract ZIP archives
- Organize recordings and screenshots
- Move deleted items to the recycle bin or trash when possible

### System Settings Assistant

- Open relevant operating-system settings
- Audio and microphone settings
- Display and brightness settings
- Wi-Fi and Bluetooth settings
- Storage and battery settings
- Notifications and appearance settings
- Only change values supported by the current platform

### Diagnostics

- CPU, memory, disk, battery, process, and network checks
- Low-storage warnings
- Application failure detection
- User-approved log reading
- Safe troubleshooting recommendations

## Safety model

### Safe actions

These may run immediately:

- Open an application
- Open a settings page
- Search files
- Read system status

### Confirmation required

These require user approval:

- Start recording
- Close or restart an application
- Change system settings
- Move many files
- Install or uninstall software
- Restart or shut down a device

### Restricted actions

The assistant must block or strictly restrict:

- Secret screen, camera, or microphone recording
- Permission bypassing
- Disabling security protection
- Unrestricted AI-generated shell execution
- Permanent deletion without confirmation
- Sending private files without permission
- Financial transactions

## Architecture

```text
User command
    ↓
Language detection
    ↓
AI command parser
    ↓
Command planner
    ↓
Risk classifier
    ↓
Permission and capability check
    ↓
User confirmation when required
    ↓
Native platform adapter
    ↓
Action result
    ↓
Activity log
```

## Project structure

```text
phakphum_ai_assistant/
├── lib/
│   ├── main.dart
│   ├── app/
│   ├── screens/
│   ├── ai_engine/
│   ├── core/
│   ├── services/
│   └── platform/
├── windows/
├── macos/
├── linux/
├── android/
├── ios/
├── web/
├── assets/
├── test/
├── integration_test/
├── docs/
├── README.md
├── PROJECT_SPEC.txt
└── pubspec.yaml
```

## Standard command format

```json
{
  "id": "cmd_20260727_001",
  "action": "screen_recording.start",
  "parameters": {
    "source": "display",
    "microphone": true,
    "systemAudio": true,
    "quality": "1080p",
    "fps": 30,
    "countdownSeconds": 3
  },
  "risk": "permission_required",
  "requiresConfirmation": true
}
```

## Platform implementation

### Windows

- Windows Graphics Capture
- Native audio APIs
- Process APIs
- Windows Settings URI
- Allowlisted PowerShell commands only

### macOS

- ScreenCaptureKit
- NSWorkspace
- Apple permission system
- Accessibility access only after user approval

### Linux

- XDG Desktop Portal
- PipeWire
- D-Bus
- X11 fallback where needed
- Desktop-specific adapters

### Android

- MediaProjection
- Foreground Service
- Storage Access Framework
- Android intents

### iOS / iPadOS

- ReplayKit
- Document picker
- URL schemes and universal links
- App-scoped access only

### Web

- Browser Screen Capture API
- MediaRecorder
- Browser file APIs
- Browser sandbox restrictions

## Ad and tracker blocking

The application includes an optional privacy module for blocking advertisements,
trackers, pop-ups, automatic redirects, and selected autoplay media where the
current platform permits it.

### Supported scopes

- **Application UI:** the application itself contains no third-party advertising
  and can hide optional promotional panels.
- **Embedded WebView:** blocks known ad and tracking requests, hides common ad
  containers, and stops pop-ups.
- **Browser extension:** optional filtering for supported desktop browsers.
- **DNS filtering:** blocks known advertising, tracking, phishing, and malware
  domains after explicit user enablement.
- **Local VPN filtering:** may be used on Android after the user grants permission.
- **Safari content blocker:** may be used on iPhone, iPad, and macOS within
  Apple's approved content-blocking system.

### Example commands

```text
บล็อกโฆษณาในเว็บไซต์นี้
ปิดป๊อปอัป
อนุญาตโฆษณาเฉพาะเว็บนี้
เปิดโหมดป้องกันการติดตาม
แสดงรายการที่ถูกบล็อก
หยุดบล็อกโฆษณาชั่วคราว 10 นาที
อัปเดตรายการตัวกรอง
```

### Standard action

```json
{
  "id": "cmd_20260727_002",
  "action": "content_filter.enable",
  "parameters": {
    "scope": "webview",
    "blockAds": true,
    "blockTrackers": true,
    "blockPopups": true,
    "blockAutoplay": false,
    "site": "current"
  },
  "risk": "safe",
  "requiresConfirmation": false
}
```

### Privacy rules

- No advertisements are injected into the application.
- Browsing history is not sold or uploaded without permission.
- Passwords, payment pages, and private messages are never inspected.
- HTTPS traffic is not decrypted by default.
- Filter logs stay on the device unless the user exports them.
- Users can pause protection or allow a site at any time.
- Essential operating-system and security-update services must not be blocked.
- Banking, payment, health, and government websites use conservative filtering.

### Recommended interface

```text
Privacy & Ad Blocking
├── Protection: On / Off
├── Ads blocked
├── Trackers blocked
├── Block pop-ups
├── Block autoplay
├── Allow current site
├── Filter-list status
├── Custom rules
├── Activity log
└── Pause protection
```

### Platform limitations

- **Windows, macOS, Linux:** application-level, browser-extension, DNS, or proxy
  filtering may be available.
- **Android:** WebView filtering, private DNS guidance, or local-VPN filtering
  may be available after permission.
- **iOS / iPadOS:** Safari content blockers, approved network extensions, and
  application WebView filtering are supported, but unrestricted filtering of
  every application is not available.
- **Web:** can filter only inside the web application unless a browser extension
  is installed.
- Ads embedded directly into video streams or server-rendered content may not
  be removable without breaking the content.

## Development roadmap

1. Build the shared Flutter interface and action models.
2. Add permission, risk, logging, and emergency-stop systems.
3. Implement the Windows adapter.
4. Implement Android and Linux adapters.
5. Implement macOS and iOS adapters.
6. Implement the web recorder.
7. Add ad, tracker, pop-up, and DNS filtering.
8. Add Thai speech recognition and offline command support.
9. Add multi-step troubleshooting and command templates.

## Build outputs

```text
Windows   → .exe / .msix
macOS     → .app / .dmg
Linux     → AppImage / .deb / Flatpak
Android   → .apk / .aab
iOS       → Xcode archive / App Store package
Web       → build/web
```

## First-version completion criteria

- Shared Flutter UI runs on every target platform.
- Capability detection reports correct platform support.
- Recording works wherever the operating system permits it.
- Important actions require approval.
- Unsupported commands return an honest message.
- Activity logs are stored locally.
- Emergency stop cancels active AI operations.
- Native adapters report real success or failure.
- Screen, camera, and microphone capture cannot operate secretly.
