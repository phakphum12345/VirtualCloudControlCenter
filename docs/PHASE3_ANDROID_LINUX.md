# Phase 3: Android and Linux

## Android foundation implemented

- Native method channel: `com.phakphum.aiassistant/android`
- Memory, storage, battery, and processor diagnostics
- Allowlisted Wi-Fi, Bluetooth, display, storage, battery, notification, and
  sound Settings intents
- Honest failure for screen recording until MediaProjection permission,
  foreground service, visible notification, and output finalization are wired

## Linux foundation implemented

- Native method channel: `com.phakphum.aiassistant/linux`
- Procfs memory, filesystem storage, and processor diagnostics
- Allowlisted GNOME Settings panels launched without shell evaluation

## Linux next

- XDG Desktop Portal permission discovery and PipeWire screen-capture lifecycle
- Desktop-specific D-Bus adapters beyond GNOME
- Battery and network diagnostics

No Android accessibility service is enabled or requested by this foundation.
