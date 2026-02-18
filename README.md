# ZebraRedact

Local PII redaction for LLM prompts. Strip sensitive data before sharing text with AI — on-device, zero network calls.

## Requirements

- macOS 15.0+
- Xcode 16+
- Apple Silicon (M1+) recommended

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

### Redaction Modes

| Mode | Description |
|------|-------------|
| **Tokens** | Replace PII with stable tokens like `[NAME_A1B2]` |
| **Fake Data** | Substitute realistic fictional values (semantic replacements) |
| **AI Classify** | On-device LLM augments detection and generates context-aware fakes |

### Detection

- **NLTagger** — names, organizations, locations (Apple NLP)
- **Regex** — email, phone, credit card, SSN, IPv4, API keys
- **LLM Augmentation** — catches entities NLTagger/regex miss (optional, on-device only)

### LLM Backends (LLM Classify mode)

Priority order, all on-device:

1. **Apple Intelligence** (`FoundationModels`, macOS 26+)
2. **Ollama** — llama3.2:3b / phi4-mini / gemma3 / mistral7b via `localhost:11434`
3. **MLX** — downloadable model via ModelManager
4. **Semantic fallback** — curated fake-data pools (always available)

### UI

- Three-panel layout: collapsible sidebar + clear text + redacted text
- Sidebar: PII type toggles, domain presets (GDPR, HIPAA, CCPA, Finance, Education, Transportation), redaction mode, AI model picker
- Click any token in the output to choose an alternative replacement
- Right-click plain text in the output to manually tag undetected PII
- "Restore original" from the token dropdown to untokenize a mistakenly tagged word
- Re-hydrate sheet: paste LLM response with tokens back → restore originals
- Copy with optional safety prompt prefix for LLMs
- Confidence quality indicator (task completability, hallucination risk, coherence)

## Architecture

```
ZebraRedact/
├── ZebraRedact/                   # Xcode target sources
│   ├── App/
│   │   └── ZebraRedactApp.swift   # @main, WindowGroup
│   ├── Models/
│   │   ├── PIIItem.swift          # PII data model + alternatives
│   │   ├── PIIType.swift          # Enum of detectable PII categories
│   │   └── ConfidenceAssessment.swift
│   ├── Services/
│   │   ├── PIIDetector.swift      # Detection orchestrator + masking pipeline
│   │   ├── NLTaggerDetector.swift # Apple NLP detection
│   │   ├── RegexDetector.swift    # Regex-based detection
│   │   ├── GhostMappingStore.swift # Token ↔ original mapping (rehydration)
│   │   ├── ModelManager.swift     # MLX model lifecycle
│   │   └── VaultManager.swift     # Keychain vault
│   └── Utilities/
│       ├── DesignSystem.swift     # Colors, typography
│       └── Constants.swift
│
└── (root — compiled into target)
    ├── MainWindow.swift           # Main UI: sidebar + panels + bottom bar
    ├── ClickableTokenTextView.swift # NSTextView with clickable + right-click tokens
    ├── RedactionMode.swift        # .token / .semantic / .llmAware
    ├── SemanticAnalyzer.swift     # Semantic replacement helpers
    ├── OllamaEngine.swift         # Ollama HTTP client + model management
    ├── LLMAwareSetupSheet.swift   # Ollama setup UI
    ├── MLXContextEngine.swift     # MLX inference stub
    └── FoundationModelEngine.swift # Apple FoundationModels engine (macOS 26+)
```

## Privacy

- All detection and inference runs entirely on-device
- No data is sent to any external server
- Vault entries stored in macOS Keychain
- `NSPrivacyTracking: false` — no tracking, no collected data types

## License

Copyright 2025 ZebraRedact. All rights reserved.
