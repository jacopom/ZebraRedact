# GhostClip

Local PII masking for LLM prompts. Ghost your sensitive data before sharing with AI.

## Requirements

- macOS 15.0+
- Xcode 16+
- Apple Silicon (M1+) recommended

## Build & Run

### From Xcode

1. Open `GhostClip.xcodeproj` in Xcode 16+
2. Select the `GhostClip` scheme
3. Press `⌘R` to build and run

### From Command Line

```bash
# Ensure Xcode is selected
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Build
xcodebuild -project GhostClip.xcodeproj -scheme GhostClip -configuration Debug build

# Archive for distribution
xcodebuild -project GhostClip.xcodeproj -scheme GhostClip -configuration Release archive -archivePath build/GhostClip.xcarchive
```

## Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌥⌘G` | Summon GhostClip overlay editor (global hotkey) |
| `⌘⏎` | Apply ghosted text to clipboard |
| `⎋` (Escape) | Dismiss overlay |
| `⌘,` | Open Settings |
| `⌘Q` | Quit |

## Features

### Free Tier
- Regex-based PII detection (email, phone, credit card, SSN, IP, API keys)
- Split-pane editor: Original text vs. Ghosted preview
- Privacy score indicator
- Global hotkey `⌥⌘G` from any app
- Menu bar status item

### Pro Tier (€19)
- MLX-powered AI PII detection (98% accuracy)
- Model management (download, install, switch, uninstall)
- Secure Vault (Keychain-backed, biometric/PIN protected)
- Rehydration support via `[GHOST_X]` tokens

## Architecture

```
GhostClip/
├── App/
│   ├── GhostClipApp.swift          # @main entry, MenuBarExtra, Settings scene
│   ├── AppDelegate.swift            # Menu bar, hotkey registration, overlay lifecycle
│   └── OverlayPanel.swift           # NSPanel for floating editor
├── Views/
│   ├── Onboarding/
│   │   └── OnboardingView.swift     # 3-slide TabView onboarding
│   ├── Editor/
│   │   ├── OverlayEditorView.swift  # Main split-pane editor
│   │   └── GhostScoreBadge.swift    # Privacy score indicator
│   └── Settings/
│       ├── SettingsView.swift       # NavigationSplitView settings
│       ├── ModelManagementView.swift # MLX model install/uninstall
│       └── VaultView.swift          # Keychain vault UI
├── Models/
│   ├── PIIItem.swift                # PII detection data model
│   └── MLXModelInfo.swift           # MLX model metadata
├── Services/
│   ├── RegexDetector.swift          # Regex-based PII detection
│   ├── PIIDetector.swift            # Detection facade (Regex/MLX)
│   ├── ModelManager.swift           # MLX model lifecycle
│   ├── VaultManager.swift           # Keychain vault operations
│   ├── HotkeyManager.swift          # Carbon global hotkey
│   └── ClipboardManager.swift       # NSPasteboard operations
├── Utilities/
│   ├── Constants.swift              # App-wide constants
│   └── Theme.swift                  # Colors (#6B46C1 purple, etc.)
└── Resources/
    ├── Assets.xcassets              # App icon, colors
    └── PrivacyInfo.xcprivacy        # Privacy manifest
```

## Flows

1. **Launch** -> Onboarding (first launch) -> Menu bar icon active
2. **⌥⌘G** -> Capture clipboard/selection -> Show overlay editor -> Edit -> Apply
3. **Pro: Model Management** -> Settings -> Pick model -> Install (progress) -> Test -> Switch/Uninstall
4. **Pro: Vault** -> Settings -> Authenticate -> Add secrets -> Use in editor

## Testing

```bash
# Build and run tests
xcodebuild -project GhostClip.xcodeproj -scheme GhostClip test

# Test PII detection manually
# The regex detector covers: email, phone, credit card, SSN, IPv4, API keys
```

## Notarized DMG

```bash
# Create archive
xcodebuild -project GhostClip.xcodeproj \
  -scheme GhostClip \
  -configuration Release \
  archive -archivePath build/GhostClip.xcarchive

# Export
xcodebuild -exportArchive \
  -archivePath build/GhostClip.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist

# Create DMG
hdiutil create -volname "GhostClip" \
  -srcfolder build/GhostClip.app \
  -ov -format UDZO \
  build/GhostClip.dmg

# Notarize (requires Apple Developer account)
xcrun notarytool submit build/GhostClip.dmg \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_PASSWORD \
  --wait
```

## Privacy

- All PII detection runs locally on-device
- No data is sent to any server
- Vault entries are stored in macOS Keychain
- NSPrivacyTracking: false
- No collected data types

## License

Copyright 2025 GhostClip. All rights reserved.
