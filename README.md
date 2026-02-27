# ZebraRedact

Local PII redaction for LLM prompts. Strip sensitive data before sharing text with AI — on-device, zero network calls.

## Requirements

- macOS 15.0+
- Xcode 16+

## Build & Run

```bash
# Build (from project root)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ZebraRedact.xcodeproj -scheme ZebraRedact -configuration Debug build

# Archive for distribution
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ZebraRedact.xcodeproj -scheme ZebraRedact -configuration Release \
  archive -archivePath build/ZebraRedact.xcarchive
```

## Features

### Detection

| Detector | Entities |
|----------|----------|
| **NLTagger** | Names, organisations, locations (Apple on-device NLP) |
| **Regex** | Email, phone (US, international, European bare 10–11 digit), credit card, SSN, IPv4, API keys |

All detection is local — no data leaves the device.

### Redaction

Detected items are replaced with stable typed tokens: `[NAME_A1B2]`, `[EMAIL_C3D4]`, `[PHONE_E5F6]`, etc.

- Same entity always gets the same token across the document
- Click any token in the output panel to pick an alternative or restore the original
- Right-click selected text in the output panel to manually tag anything auto-detection missed

### Restore Tab

Paste an LLM response that contains tokens back into the Restore tab to get the original values rehydrated inline.

### Quick Send

The **Copy Redacted** button copies the sanitised text to the clipboard. The dropdown next to it lets you:
- Copy with a safety-prompt prefix that instructs the LLM to preserve tokens
- Open ChatGPT, Claude, Perplexity, or Grok directly in the browser with an auto-paste (requires Accessibility permission)

### UI

- Twin-panel layout: input on the left, redacted output on the right
- Collapsible dark sidebar: PII type toggles, domain preset picker, redacted-items list
- Domain presets: GDPR, HIPAA, CCPA, Finance, Education, Transportation
- Spoiler-style token overlay: tokens shown as censored bars, hover to reveal the token ID
- Confidence indicator in the bottom bar (task completability, hallucination risk, coherence)
- Menu bar icon + global hotkey **⌥⌘G** to bring the window forward
- **⌘⇧C** to copy the redacted text from anywhere

## Architecture

```
ZebraRedact/
├── ZebraRedact/                    # Xcode target sources
│   ├── App/
│   │   ├── ZebraRedactApp.swift    # @main, WindowGroup, Settings scene
│   │   └── AppDelegate.swift       # NSStatusItem, hotkey, onboarding
│   ├── Models/
│   │   ├── PIIItem.swift           # PII data model + token alternatives
│   │   ├── PIIType.swift           # Enum of detectable PII categories
│   │   └── ConfidenceAssessment.swift
│   ├── Services/
│   │   ├── PIIDetector.swift       # Detection orchestrator + masking pipeline
│   │   ├── NLTaggerDetector.swift  # Apple NLP (runs on text.capitalized for lowercase coverage)
│   │   ├── RegexDetector.swift     # Pattern-based detection
│   │   └── TokenMappingStore.swift # Token ↔ original mapping (rehydration)
│   ├── Views/
│   │   ├── Onboarding/OnboardingView.swift
│   │   └── Settings/SettingsView.swift
│   └── Utilities/
│       ├── DesignSystem.swift      # Colors, typography, spacing
│       └── Constants.swift
│
└── (root — compiled into target)
    ├── MainWindow.swift            # Main UI: top bar, twin panels, sidebar, bottom bar
    └── ClickableTokenTextView.swift # NSTextView with spoiler overlay + right-click tagging
```

## Privacy

- All detection runs entirely on-device
- No data is sent to any external server
- Token mapping is stored in memory for the session only
- `NSPrivacyTracking: false` — no tracking, no collected data types

## License

Copyright 2025 ZebraRedact. All rights reserved.
