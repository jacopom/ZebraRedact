import SwiftUI

// MARK: - App Tab

enum AppTab: String, CaseIterable {
    case redact = "Redact"
    case rehydrate = "Re-hydrate"
}

// MARK: - Domain Preset

enum DomainPreset: String, CaseIterable, Identifiable {
    case none          = "None (default)"
    case gdpr          = "GDPR - General Data Protection defaults"
    case hipaa         = "HIPAA - Health data emphasis"
    case ccpa          = "CCPA - Consumer privacy defaults"
    case finance       = "Finance - Sector-focused bundle"
    case education     = "Education - Sector-focused bundle"
    case transportation = "Transportation - Sector-focused bundle"

    var id: String { rawValue }

    var enabledCategories: Set<PIIType> {
        switch self {
        case .none:           return Set(PIIType.allCases)
        case .gdpr:           return [.name, .email, .phone, .address, .ssn, .creditCard]
        case .hipaa:          return [.name, .email, .phone, .address, .ssn]
        case .ccpa:           return [.name, .email, .phone, .address, .creditCard, .ssn]
        case .finance:        return [.name, .email, .phone, .creditCard, .ssn, .apiKey]
        case .education:      return [.name, .email, .phone, .address]
        case .transportation: return [.name, .email, .phone, .address, .ipAddress]
        }
    }
}

// MARK: - Main Window

struct MainWindow: View {
    @StateObject private var detector = PIIDetector()
    @State private var inputText: String = ""
    @State private var selectedToken: PIIItem?

    // Navigation
    @State private var activeTab: AppTab = .redact

    // Sidebar
    @State private var sidebarVisible: Bool = true
    @State private var selectedDomainPreset: DomainPreset = .none
    @State private var installedOllamaModels: [String] = []
    @State private var selectedAIModelId: String = "none"

    // Popovers
    @State private var showStatusPopover: Bool = false
    @State private var showLLMSetupSheet: Bool = false

    // Sidebar state
    @State private var piiTypesExpanded: Bool = false

    // Manual tokenization
    @State private var pendingManualTokenText: String? = nil
    @State private var showManualTokenSheet: Bool = false
    @State private var manualTokenType: PIIType = .custom
    @State private var manualTokenError: String? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                HStack(spacing: 0) {
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if sidebarVisible {
                        Divider()
                        sidebarPanel
                            .frame(width: 240)
                    }
                }
                .frame(maxHeight: .infinity)
                Divider()
                bottomBar
            }

            // Alternatives dropdown overlay
            if let token = selectedToken {
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .onTapGesture { selectedToken = nil }
                    .overlay(alignment: .center) {
                        AlternativesDropdown(
                            item: token,
                            detector: detector,
                            inputText: $inputText,
                            selectedToken: $selectedToken
                        )
                        .frame(width: 300)
                        .frame(maxHeight: 500)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
                        .allowsHitTesting(true)
                        .padding(40)
                    }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showLLMSetupSheet, onDismiss: {
            Task {
                installedOllamaModels = (try? await OllamaEngine.listModels()) ?? []
                if let saved = OllamaEngine.activeModel, saved != "none" {
                    selectedAIModelId = saved
                }
            }
        }) { LLMAwareSetupSheet() }
        .sheet(isPresented: $showManualTokenSheet) {
            ManualTokenSheet(
                isPresented: $showManualTokenSheet,
                selectedText: pendingManualTokenText ?? "",
                piiType: $manualTokenType,
                errorMessage: $manualTokenError,
                onConfirm: applyManualToken
            )
        }
        .task {
            installedOllamaModels = (try? await OllamaEngine.listModels()) ?? []
            if let saved = OllamaEngine.activeModel {
                selectedAIModelId = saved
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()

            // Centered pill tab switcher
            tabSwitcher

            Spacer()

            // Right side: AI badge + LLM setup + sidebar toggle
            HStack(spacing: 8) {
                if detector.isFoundationModelsActive || detector.isOllamaActive {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("AI")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple)
                    .cornerRadius(10)
                }

                Button(action: { showLLMSetupSheet = true }) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("LLM-Aware Setup")

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundColor(sidebarVisible ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
                .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundColor(activeTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeTab == tab
                                      ? Color(NSColor.controlBackgroundColor)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(NSColor.separatorColor).opacity(0.4))
        )
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            switch activeTab {
            case .redact:
                redactContent
            case .rehydrate:
                rehydrateContent
            }
        }
    }

    private var redactContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: .black.opacity(0.09), radius: 8, x: 0, y: 2)

            VStack(spacing: 0) {
                panelHeaders
                Divider()
                HStack(spacing: 0) {
                    inputPanel
                        .frame(maxWidth: .infinity)
                    Divider()
                    outputPanel
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(12)
    }

    private var rehydrateContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: .black.opacity(0.09), radius: 8, x: 0, y: 2)

            InlineRehydrateView()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(12)
    }

    // MARK: - Sidebar (right, dark)

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Redacted Items
                    if !detector.detectedItems.isEmpty {
                        darkSection(title: "Redacted Items") {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(detector.detectedItems) { item in
                                    Button(action: {
                                        activeTab = .redact
                                        selectedToken = item
                                    }) {
                                        HStack(spacing: 8) {
                                            Capsule()
                                                .fill(item.type.highlightColor)
                                                .frame(width: 4, height: 14)
                                            Text(item.originalText)
                                                .font(.system(size: 11, design: .monospaced))
                                                .lineLimit(1)
                                                .foregroundColor(Color.white.opacity(0.85))
                                            Spacer()
                                            Text(String(item.type.rawValue.prefix(5)))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(item.type.highlightColor)
                                        }
                                        .padding(.vertical, 5)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                    }

                    // PII Types (collapsible)
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) { piiTypesExpanded.toggle() }
                        }) {
                            HStack(spacing: 6) {
                                Text("PII Types")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.45))
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Spacer()
                                Text(piiTypeSummaryLabel)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.white.opacity(0.35))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .rotationEffect(.degrees(piiTypesExpanded ? 90 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        if piiTypesExpanded {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(PIIType.allCases, id: \.self) { type in
                                    let count = detector.detectedItems.filter { $0.type == type }.count
                                    Toggle(isOn: Binding(
                                        get: { detector.enabledCategories.contains(type) },
                                        set: { _ in
                                            detector.toggleCategory(type)
                                            if !inputText.isEmpty { detector.scan(text: inputText) }
                                        }
                                    )) {
                                        HStack(spacing: 0) {
                                            Text(type.rawValue)
                                                .font(.system(size: 12))
                                            Spacer()
                                            if count > 0 {
                                                Text("\(count)")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(type.highlightColor)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(type.highlightColor.opacity(0.2))
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    // Domain preset
                    darkSection(title: "Domain") {
                        Picker("", selection: $selectedDomainPreset) {
                            ForEach(DomainPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: selectedDomainPreset) { _, preset in
                            applyDomainPreset(preset)
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    // Redaction Mode
                    darkSection(title: "Mode") {
                        Picker("", selection: $detector.redactionMode) {
                            Text("Tokens").tag(RedactionMode.token)
                            Text("Fake Data").tag(RedactionMode.semantic)
                            Text("AI Classify").tag(RedactionMode.llmAware)
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: detector.redactionMode) { _, mode in
                            if mode == .llmAware, selectedAIModelId != "none" {
                                OllamaEngine.activeModel = selectedAIModelId
                            }
                            if !inputText.isEmpty { detector.remaskCurrentItems(originalText: inputText) }
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    // AI Model
                    darkSection(title: "AI Model") {
                        Picker("", selection: $selectedAIModelId) {
                            Text("None (Semantic)").tag("none")
                            if !installedOllamaModels.isEmpty {
                                Divider()
                                ForEach(installedOllamaModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: selectedAIModelId) { _, modelId in
                            applyAIModelSelection(modelId)
                        }

                        if detector.redactionMode == .llmAware {
                            HStack(spacing: 4) {
                                Image(systemName: aiBackendStatus.icon)
                                    .font(.system(size: 10))
                                Text(aiBackendStatus.label)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(aiBackendStatus.color)
                            .padding(.top, 2)
                        }

                        if installedOllamaModels.isEmpty {
                            Button("Download a model…") { showLLMSetupSheet = true }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(red: 0.13, green: 0.13, blue: 0.15))
        .colorScheme(.dark)
    }

    @ViewBuilder
    private func darkSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Panel Headers

    private var panelHeaders: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Clear text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if !inputText.isEmpty {
                    Button(action: { inputText = ""; detector.detectedItems = [] }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Spacer()
                Text("Redacted text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        ZStack(alignment: .center) {
            InputTextView(
                text: $inputText,
                highlightRange: selectedToken?.range,
                highlightColor: selectedToken?.type.highlightColor ?? .clear,
                onTextChange: { newText in detector.scan(text: newText) }
            )

            if inputText.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.tertiary)
                    Text("Paste or type to scan")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button(action: pasteFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button(action: loadSampleText) {
                            Label("Sample", systemImage: "text.document")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Output Panel

    private var outputPanel: some View {
        ZStack {
            Group {
                if inputText.isEmpty {
                    Color.clear
                } else if detector.detectedItems.isEmpty && !detector.isProcessing {
                    noDetectionsState
                } else {
                    ClickableTokenTextView(
                        text: detector.ghostedText,
                        items: detector.detectedItems,
                        onTokenClick: { item in selectedToken = item },
                        onTextSelection: { selectedText in
                            pendingManualTokenText = selectedText
                            manualTokenType = .custom
                            manualTokenError = nil
                            showManualTokenSheet = true
                        },
                        appliedTexts: detector.appliedReplacements
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if detector.isProcessing && !inputText.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Analyzing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var noDetectionsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(DesignSystem.Colors.success)
            Text("No PII detected")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.tertiary)
                    Text("\(wordCount) words")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if !detector.detectedItems.isEmpty {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.tertiary)
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.warning)
                        Text("\(detector.detectedItems.count) PII detected")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if detector.isProcessing {
                    ProgressView().controlSize(.mini).padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)

            Divider().frame(height: 20)

            HStack(spacing: 8) {
                if let assessment = detector.confidenceAssessment {
                    Button(action: { showStatusPopover.toggle() }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorForStatus(assessment.status))
                                .frame(width: 7, height: 7)
                            Text(assessment.statusText)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(colorForStatus(assessment.status).opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(colorForStatus(assessment.status).opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStatusPopover, arrowEdge: .top) {
                        StatusPopover(assessment: assessment)
                    }
                }

                if !detector.ghostedText.isEmpty {
                    HStack(spacing: 0) {
                        Button(action: { copyToClipboard(detector.ghostedText) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc").font(.system(size: 11))
                                Text("Copy Redacted").font(.system(size: 11))
                            }
                            .padding(.leading, 9)
                            .padding(.trailing, 6)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 16)

                        Menu {
                            Button(action: copyWithSafetyPrompt) {
                                Label("Copy with Safety Prompt", systemImage: "lock.doc")
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Computed

    private var wordCount: Int {
        inputText.split(separator: " ").count
    }

    private var piiTypeSummaryLabel: String {
        let enabled = detector.enabledCategories.count
        let total = PIIType.allCases.count
        return enabled == total ? "All \(total)" : "\(enabled) of \(total)"
    }

    // MARK: - Color Helper

    private func colorForStatus(_ status: ConfidenceStatus) -> Color {
        switch status {
        case .ready:        return DesignSystem.Colors.success
        case .reviewNeeded: return DesignSystem.Colors.warning
        case .tooDegraded:  return DesignSystem.Colors.error
        }
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func copyWithSafetyPrompt() {
        let prompt = """
        [Context for AI model]
        The text below contains privacy tokens in the format [TYPE_XXXX]. These tokens replace \
        sensitive personal information. Please:
        - Preserve all tokens exactly as written (e.g. [NAME_A1B2], [EMAIL_C3D4])
        - Do not attempt to guess, infer, or restore the original values
        - Include the tokens unchanged wherever that information would appear in your response

        ---

        \(detector.ghostedText)
        """
        copyToClipboard(prompt)
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            inputText = text
            detector.scan(text: text)
        }
    }

    private func loadSampleText() {
        inputText = """
        Hi team, please update the account for John Smith.

        Email: john.smith@acme-corp.com
        Phone: +1 (555) 867-5309
        Credit Card: 4111-1111-1111-1111
        SSN: 123-45-6789
        Server: 192.168.1.100
        API Key: sk-proj1234567890abcdefghij1234567890

        Thanks, Sarah
        """
        detector.scan(text: inputText)
    }

    private func applyDomainPreset(_ preset: DomainPreset) {
        detector.enabledCategories = preset.enabledCategories
        if !inputText.isEmpty { detector.scan(text: inputText) }
    }

    private var aiBackendStatus: (label: String, color: Color, icon: String) {
        if detector.isFoundationModelsActive {
            return ("Apple Intelligence", .green, "apple.intelligence")
        }
        if selectedAIModelId != "none" {
            let shortName = selectedAIModelId.components(separatedBy: ":").first ?? selectedAIModelId
            return ("Ollama · \(shortName)", .green, "antenna.radiowaves.left.and.right")
        }
        return ("NL Analysis (no model)", .orange, "wand.and.sparkles")
    }

    private func applyAIModelSelection(_ modelId: String) {
        if modelId == "none" {
            OllamaEngine.activeModel = nil
            if detector.redactionMode == .llmAware {
                detector.redactionMode = .semantic
            }
        } else {
            OllamaEngine.activeModel = modelId
            detector.redactionMode = .llmAware
        }
        if !inputText.isEmpty { detector.scan(text: inputText) }
    }

    private func applyManualToken() {
        guard let text = pendingManualTokenText, !text.isEmpty else { return }
        guard let range = inputText.range(of: text, options: .literal) else {
            manualTokenError = "Could not find \"\(text)\" in input text"
            return
        }
        do {
            try detector.addManualTag(range: range, type: manualTokenType, in: inputText)
            showManualTokenSheet = false
        } catch {
            manualTokenError = error.localizedDescription
        }
    }
}

// MARK: - Status Popover

struct StatusPopover: View {
    let assessment: ConfidenceAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redaction Quality")
                .font(.system(size: 13, weight: .semibold))

            Text(assessment.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                MetricRow(
                    label: "Task completability",
                    value: assessment.taskCompletability,
                    direction: .higher
                )
                MetricRow(
                    label: "Hallucination risk",
                    value: assessment.hallucinationRisk,
                    direction: .lower
                )
                MetricRow(
                    label: "Coherence",
                    value: assessment.coherence,
                    direction: .higher
                )
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

private struct MetricRow: View {
    enum Direction { case higher, lower }

    let label: String
    let value: Int
    let direction: Direction

    private var barColor: Color {
        let good = direction == .higher ? value >= 70 : value <= 30
        let bad  = direction == .higher ? value < 40  : value > 70
        return good ? .green : bad ? .red : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)%")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 5)
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(value) / 100, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Inline Re-hydrate View

struct InlineRehydrateView: View {
    @State private var pastedText: String = ""
    @State private var tokenCount: Int = 0

    private var rehydrated: String {
        GhostMappingStore.shared.rehydrate(pastedText)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: input with tokens
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Text with tokens")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if tokenCount > 0 {
                        Text("\(tokenCount) token\(tokenCount == 1 ? "" : "s") found")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                TextEditor(text: $pastedText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .onChange(of: pastedText) { _, text in
                        tokenCount = GhostMappingStore.shared.rehydrationCount(in: text)
                    }
            }

            Divider()

            // Right: rehydrated output
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Restored text")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !rehydrated.isEmpty && rehydrated != pastedText {
                        Button(action: {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(rehydrated, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                ScrollView {
                    Text(pastedText.isEmpty
                         ? "Paste text with tokens on the left…"
                         : rehydrated)
                        .font(pastedText.isEmpty ? .callout : .body)
                        .foregroundColor(pastedText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Manual Token Sheet

struct ManualTokenSheet: View {
    @Binding var isPresented: Bool
    let selectedText: String
    @Binding var piiType: PIIType
    @Binding var errorMessage: String?
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tag as PII")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Selected text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(selectedText)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1.0, green: 0.92, blue: 0.7))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PII Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("PII Type", selection: $piiType) {
                    ForEach(PIIType.allCases, id: \.self) { type in
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                            Text(type.rawValue)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Tag as \(piiType.rawValue)") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360, height: 540)
    }
}

// MARK: - Alternatives Dropdown

struct AlternativesDropdown: View {
    let item: PIIItem
    @ObservedObject var detector: PIIDetector
    @Binding var inputText: String
    @Binding var selectedToken: PIIItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Original:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.originalText)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.type.highlightColor.opacity(0.7))
                            .cornerRadius(4)
                    }
                    HStack(spacing: 6) {
                        Text("Token:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.ghostToken)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Text(item.type.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                Button { selectedToken = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.alternatives) { alternative in
                        AlternativeRow(
                            alternative: alternative,
                            isSelected: alternative.id == item.selectedAlternativeId,
                            onSelect: { selectAlternative(alternative) }
                        )
                    }

                    Button(action: restoreOriginal) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Restore original")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Text("Remove tag, show original text")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(maxHeight: 450)
        }
        .onHover { hovering in
            if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
        }
    }

    private func selectAlternative(_ alternative: RedactionAlternative) {
        if let index = detector.detectedItems.firstIndex(where: { $0.id == item.id }) {
            detector.detectedItems[index].selectedAlternativeId = alternative.id
            detector.remask(originalText: inputText)
            detector.objectWillChange.send()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { selectedToken = nil }
    }

    private func restoreOriginal() {
        detector.removeItem(item, originalText: inputText)
        selectedToken = nil
    }
}

struct AlternativeRow: View {
    let alternative: RedactionAlternative
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alternative.text)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(alternative.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.15) :
                          isHovered  ? Color.gray.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Input Text View

struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    let highlightRange: Range<String.Index>?
    let highlightColor: Color
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = CGSize(width: 16, height: 16)
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            if sel.location <= text.count { textView.setSelectedRange(sel) }
        }
        if let storage = textView.textStorage {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
            if let range = highlightRange, !text.isEmpty {
                let nsRange = NSRange(range, in: text)
                if nsRange.location != NSNotFound, nsRange.location + nsRange.length <= storage.length {
                    storage.addAttribute(.backgroundColor,
                                         value: NSColor(highlightColor).withAlphaComponent(0.6),
                                         range: nsRange)
                    textView.scrollRangeToVisible(nsRange)
                }
            }
        }
        context.coordinator.onTextChange = onTextChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onTextChange: onTextChange) }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onTextChange: (String) -> Void
        init(text: Binding<String>, onTextChange: @escaping (String) -> Void) {
            _text = text; self.onTextChange = onTextChange
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string; onTextChange(tv.string)
        }
    }
}

#Preview {
    MainWindow().frame(width: 960, height: 680)
}
