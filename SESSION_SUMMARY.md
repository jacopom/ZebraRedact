# Session Summary - 2026-02-18

## ✅ Completed This Session

### 1. Ollama Integration (from previous session)
- Created `OllamaEngine.swift` — HTTP client for Ollama (`localhost:11434`): list models, pull model (streaming), generate
- Created `LLMAwareSetupSheet.swift` — model download UI with progress bars, active model selection
- Wired Ollama as Priority 2 in `PIIDetector.llmAware` branch (after Foundation Models, before MLX)
- Added "LLM-Aware Setup" to top bar

### 2. Ollama UUID Matching Fix
- **Problem**: Small models (llama3.2:3b) can't reliably reproduce 36-char UUIDs → output showed `[CUSTOM_8F73]` raw tokens instead of context-aware replacements
- **Fix**: Changed `OllamaReplacementEntry` from `{id, replacement}` to `{original, replacement}` — match by original text string instead

### 3. UI Redesign (wireframe-driven)
- Three-panel layout: collapsible sidebar (220 px) + "Clear text" + "Redacted text"
- Sidebar: PII type checkboxes, domain preset picker, redaction mode (radio), AI model picker
- `DomainPreset` enum with 7 compliance presets (GDPR, HIPAA, CCPA, Finance, Education, Transportation)
- Status quality pill (READY / REVIEW / DEGRADED) with popover showing 3 metrics
- Re-hydrate sheet: paste token-bearing LLM response → restore originals
- Split copy button: direct copy + chevron dropdown for "Copy with Safety Prompt"

### 4. Four UI Improvements
- Mode picker (Tokens / Fake Data / AI Classify) in sidebar
- Spinner overlay in redacted text panel during processing
- Always-rendered NSTextView for instant Cmd+V paste without clicking
- AI model selection syncs with mode picker (selecting None reverts to Fake Data if in AI Classify)

### 5. Bug Fix — Token Clickability Race Condition
- **Problem**: Tokens sometimes appeared but were not clickable/selectable
- **Root cause**: `detectedItems` was set synchronously in `scan()`, but `ghostedText` updated asynchronously later. `ClickableTokenTextView` saw new items in a stale text, found no match positions, and set no `.link` attributes
- **Fix**: Removed early `detectedItems` assignment from `scan()`. Refactored `applyMasking(to:newItems:)` to work from a local `items` copy, then update `detectedItems` and `ghostedText` atomically in the same `MainActor.run` block

### 6. Feature — Untokenize / Restore Original Text
- **New**: `PIIDetector.removeItem(_:originalText:)` — removes item from `detectedItems`, strips its `appliedReplacements` entry, rebuilds `ghostedText` from `originalText` using remaining items
- **UI**: "Restore original" row at the bottom of the `AlternativesDropdown` list (arrow.uturn.backward icon)
- Use case: auto-detection tagged a word incorrectly → user clicks token → "Restore original" → word reverts to plain text, item removed

---

## 📊 Git History

| Commit | Description |
|--------|-------------|
| `e75ddd0` | fix: Token click highlighting and UI improvements |
| `d39a3cc` | docs: Add session summary with completed work and TODO list |
| `c37e7e4` | refactor: Rebrand from GhostClip to ZebraRedact + Hemingway colors |
| `da32ec9` | fix: Entity deduplication, context menu, and bidirectional highlighting |
| `d1d45ad` | feat: Add MainWindow with clickable tokens and alternatives system |

---

## 🗂 Key Files

| File | Purpose |
|------|---------|
| `MainWindow.swift` | Main UI: sidebar, panels, bottom bar, sheets |
| `ClickableTokenTextView.swift` | NSTextView with token links + right-click tagging |
| `ZebraRedact/Services/PIIDetector.swift` | Detection orchestrator + masking pipeline |
| `OllamaEngine.swift` | Ollama HTTP client |
| `LLMAwareSetupSheet.swift` | Ollama model download UI |
| `FoundationModelEngine.swift` | Apple Intelligence engine (macOS 26+) |
| `RedactionMode.swift` | `.token` / `.semantic` / `.llmAware` |

---

## 🎯 Remaining TODOs

### P0 — Critical
- None known

### P1 — Polish
- Preserve existing tokens when user edits input text (re-scan loses manual tags)
- Keyboard shortcut for "Copy Redacted" (e.g. ⌘⇧C)

### P2 — Future
- Foundation Models (`FoundationModelEngine`) — live once macOS 26 ships
- MLX engine — needs `mlx-swift` SPM package + model download UI wiring
- Export / history log
