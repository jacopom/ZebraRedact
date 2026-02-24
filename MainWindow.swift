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
    @AppStorage("domainPreset") private var selectedDomainPreset: DomainPreset = .none
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
                            itemId: token.id,
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
        ZStack {
            // Tab switcher centered over content area only (excludes sidebar width)
            HStack {
                Spacer()
                tabSwitcher
                Spacer()
            }
            .padding(.trailing, sidebarVisible ? 240 : 0)
            .animation(.easeInOut(duration: 0.18), value: sidebarVisible)

            // Right-side controls pinned to trailing edge
            HStack {
                Spacer()
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

            HStack(spacing: 0) {
                inputPanel
                    .frame(maxWidth: .infinity)
                Divider()
                outputPanel
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

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
                        .fill(Color.white.opacity(0.06))
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
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    // Redaction Mode — dropdown
                    darkSection(title: "Mode") {
                        Picker("", selection: $detector.redactionMode) {
                            Text("Tokens").tag(RedactionMode.token)
                            Text("Fake Data").tag(RedactionMode.semantic)
                            Text("AI Classify").tag(RedactionMode.llmAware)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: detector.redactionMode) { _, mode in
                            if mode == .llmAware, selectedAIModelId != "none" {
                                OllamaEngine.activeModel = selectedAIModelId
                            }
                            if !inputText.isEmpty { detector.remaskCurrentItems(originalText: inputText) }
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    // AI Model — dimmed when not in AI Classify mode
                    let aiActive = detector.redactionMode == .llmAware
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
                        .disabled(!aiActive)

                        if aiActive {
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
                                .disabled(!aiActive)
                        }
                    }
                    .opacity(aiActive ? 1.0 : 0.38)
                    .help(aiActive ? "" : "Compatible with AI Classify mode only")

                    // Redacted Items — shown below AI Model
                    if !detector.detectedItems.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)

                        darkSection(title: "Redacted Items") {
                            VStack(alignment: .leading, spacing: 1) {
                                // Deduplicate by originalText — multiple occurrences of the same
                                // entity are all redacted but shown as one entry in the list.
                                ForEach(uniqueRedactedItems) { item in
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
                    }
                }
            }
            Spacer(minLength: 0)

            // Settings link pinned to sidebar bottom
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            Button(action: {
                // Use the standard Cocoa action so SwiftUI's Settings scene opens correctly
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("Settings")
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundColor(Color.white.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        .foregroundStyle(.tertiary)
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
        .overlay(alignment: .topTrailing) {
            if !inputText.isEmpty {
                Button(action: { inputText = ""; detector.detectedItems = [] }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
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
                        text: detector.redactedText,
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
                .foregroundColor(Color.green)
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
                        .foregroundColor(Color.secondary.opacity(0.5))
                    Text("\(wordCount) words")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if !detector.detectedItems.isEmpty {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.5))
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color.orange)
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

                if !detector.redactedText.isEmpty {
                    HStack(spacing: 0) {
                        Button(action: { copyToClipboard(detector.redactedText) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc").font(.system(size: 11))
                                Text("Copy Redacted").font(.system(size: 11))
                            }
                            .padding(.leading, 9)
                            .padding(.trailing, 6)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("c", modifiers: [.command, .shift])

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
                        .menuIndicator(.hidden)
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

    /// Deduplicated items for sidebar display — one entry per unique original text.
    /// All occurrences are still redacted; this just avoids showing "Maya" twice.
    private var uniqueRedactedItems: [PIIItem] {
        var seen = Set<String>()
        return detector.detectedItems.filter { seen.insert($0.originalText.lowercased()).inserted }
    }

    private var piiTypeSummaryLabel: String {
        let enabled = detector.enabledCategories.count
        let total = PIIType.allCases.count
        return enabled == total ? "All \(total)" : "\(enabled) of \(total)"
    }

    // MARK: - Color Helper

    private func colorForStatus(_ status: ConfidenceStatus) -> Color {
        switch status {
        case .ready:        return Color.green
        case .reviewNeeded: return Color.orange
        case .tooDegraded:  return Color.red
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

        \(detector.redactedText)
        """
        copyToClipboard(prompt)
    }

    private func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            inputText = text
            detector.scan(text: text)
        }
    }

    private static let sampleTexts: [String] = [
        // GDPR — Employee onboarding
        """
        From: HR Department <hr@eigenvalence.eu>
        Subject: New employee onboarding — access provisioning

        Please create system accounts for our new hire starting Monday.

        Full name: Martina Brückner
        Date of birth: 14/03/1988
        Personal email: m.bruckner.privat@gmx.de
        Work phone: +49 30 4059 7821
        Home address: Prenzlauer Allee 218, 10405 Berlin, Germany
        Tax ID: 42 345 678 901 (Steueridentifikationsnummer)
        IBAN: DE89 3704 0044 0532 0130 00

        Please ensure GDPR Article 25 compliance — do not share details outside the IT provisioning workflow.

        Regards,
        Ingrid Sörensen, HR Manager
        """,

        // GDPR — Customer data deletion request
        """
        Customer complaint reference: EU-2024-08814

        I am writing on behalf of the customer below regarding a billing dispute and a GDPR Article 17 erasure request.

        Customer: Jean-Claude Morin
        Email: jcmorin77@free.fr
        Phone: +33 6 12 34 56 78
        Address: 12 impasse des Lilas, 69003 Lyon, France
        EU National ID: 1770369123456 78 (French INSEE)

        Date of disputed charge: 22 July 2024
        Amount: €349.90 (order #FR-2024-7741)

        The customer reports the amount was debited twice. Please process a full refund and permanently remove all payment data per the erasure request.
        """,

        // HIPAA — Patient referral
        """
        PATIENT REFERRAL — CONFIDENTIAL (HIPAA Protected)

        Referring physician: Dr. Amara Osei-Bonsu, MD — NPI: 1234567890
        Facility: Northlake Family Medicine, 3401 N. Milwaukee Ave, Chicago IL 60641

        Patient: Gerald Whitmore
        DOB: September 3, 1952
        SSN: 516-44-7823
        Insurance: Blue Cross PPO — Member ID 9901234567, Group 48821

        Primary DX: Type 2 Diabetes Mellitus (E11.9), Hypertensive heart disease (I11.9)
        Current medications: Metformin 1000mg BID, Lisinopril 10mg QD, Atorvastatin 40mg QD
        Reason for referral: Elevated HbA1c (9.2%) — endocrinology evaluation requested

        Patient phone: (312) 555-0178
        Emergency contact: Patricia Whitmore (wife) — (312) 555-0199
        """,

        // HIPAA — Pre-authorization request
        """
        Pre-Authorization Request — Riverside Orthopedic Group
        Contact: Cynthia Park, Billing — cpark@riverside-ortho.com — (714) 555-0134

        Patient name: Daniela Reyes-Vega
        Date of birth: 06/18/1979
        Member ID: UHC-W1234567-01 (United HealthCare)

        Procedure: Total knee arthroplasty, right — CPT 27447
        ICD-10: M17.11 (primary osteoarthritis, right knee)
        Facility: Riverside Medical Center, 3500 University Ave, Riverside CA 92501
        Estimated surgery date: March 14, 2025

        Patient phone: (951) 555-0162
        Patient email: dreyes1979@icloud.com
        """,

        // CCPA — Data deletion opt-out
        """
        Subject: CCPA Data Deletion and Opt-Out Request — Order #US-2024-901432

        I am exercising my rights under the California Consumer Privacy Act to request deletion of all personal data you hold about me and to opt out of any sale or sharing of my information.

        Name: Jasmine L. Tran
        California address: 4820 Sunset Blvd Apt 302, Los Angeles CA 90027
        Email: jasmine.tran.la@gmail.com
        Phone: (213) 555-0147
        Credit card (last 4): 4411 **** **** 7732
        Date of last purchase: November 2, 2024

        Please confirm deletion within 45 days as required by law.
        """,

        // CCPA — App user data export
        """
        User data export requested — reference #CCPA-2025-00881

        Display name: @surf_mikey_sd
        Legal name: Michael Aguilar-Santos
        Email: m.aguilar.santos@proton.me
        Phone: +1 (619) 555-0183
        Device ID: iPhone 15 Pro — UUID a4b8c2d1-e5f6-4890-ab12-cd34ef567890
        IP address (last login): 76.94.118.22 — San Diego, CA
        Payment method: Visa ending 4912 (exp 09/26)
        Account created: January 14, 2023
        Linked social: Instagram @surf_mikey_sd, Strava ID 8847321
        """,

        // Finance — Wire transfer instruction
        """
        PRIVATE & CONFIDENTIAL — Wire Transfer Instructions

        Client: Fontaine Capital Partners LLC
        Authorized signatory: Richard H. Fontaine III
        EIN: 84-3210987
        Contact: richard.fontaine@fontainecap.com | +1 (212) 555-0134

        Originating account: Chase Private Client — Acct 000482991703, ABA 021000021
        Beneficiary: Bayshore Investment Holdings Ltd
        Beneficiary bank: HSBC, 1 Queen's Road Central, Hong Kong — SWIFT: HSBCHKHHHKH
        Beneficiary account: 808-123456-838

        Amount: USD 2,450,000.00
        Purpose: Real estate acquisition deposit — 40 Hudson Yards Unit 72B
        """,

        // Finance — Trade confirmation
        """
        Trade Confirmation — Execution Report

        Account holder: Nadia Petrova-Kessler
        Account number: IB-R4591823 (Interactive Brokers)
        SSN: 219-77-4450
        Email: nkessler.trading@outlook.com
        Phone: (650) 555-0192

        Trade executed: 2024-11-14 09:32:04 EST
        Symbol: NVDA — Action: BUY 500 shares @ $147.28
        Total: $73,640.00 — Commission: $0.00
        Settlement: T+1, November 15, 2024
        Clearing: DTCC participant 0534
        """,

        // Education — Student record (FERPA)
        """
        FERPA-Protected Student Record — DO NOT DISTRIBUTE

        Student: Lorenzo Esposito-Marchetti
        Student ID: STU-20240387
        Date of birth: April 22, 2006
        Parent/guardian: Carmela Esposito — carmela.esposito@famiglia.it — +39 02 1234 5678
        Emergency contact: Marco Marchetti (father) — (617) 555-0196
        Home address: 88 Fenway Park Drive, Apt 4C, Boston MA 02215

        GPA: 3.74 (Weighted)
        IEP flag: Yes — extended time on assessments (504 Plan, ADHD)
        Health: EpiPen on file — tree nut allergy
        Counselor: Ms. Preethi Nair — pnair@boston-academy.edu
        """,

        // Education — Parent incident communication
        """
        To: David & Yuki Tanaka-Hoffman <dtyh@gmail.com>
        From: Principal Serena Abubakar <s.abubakar@westfield-elementary.edu>
        Subject: Confidential — Incident Report re: Maya Tanaka-Hoffman, Grade 3

        Dear Mr. and Mrs. Tanaka-Hoffman,

        I am writing regarding an incident on November 19 involving your daughter Maya (DOB 08/11/2016, Student ID WE-4412). Maya was involved in a conflict during recess. No injuries were sustained.

        We request your presence at a meeting on November 22 at 9:00 AM. Please contact our office at (503) 555-0167 or reply to this email to confirm. If you need Japanese/English interpretation services, please advise in advance.

        Sincerely, Principal Serena Abubakar
        """,

        // Transportation — Ride receipt
        """
        RideCo Driver Receipt — Trip #TRP-20241118-88401

        Passenger: Aleksei Volkov
        Email: a.volkov.sf@yandex.com
        Phone: +1 (415) 555-0128

        Pickup: 580 California St, San Francisco CA 94104 (06:48 AM)
        Dropoff: SFO Airport — Terminal 3 (07:31 AM)
        Duration: 43 min | Distance: 14.2 mi

        Driver: Fatou Diallo — 2022 Toyota Camry — Plate: 7XMN449
        Driver phone: (415) 555-0143

        Fare: Base $18.50 + Surge $5.55 + Tolls $6.00 = $30.05
        Payment: Amex ending 3847
        """,

        // Transportation — Fleet compliance alert
        """
        Fleet Management Alert — Vehicle Out of Compliance

        Fleet operator: Cascadia Freight Solutions Inc.
        Fleet manager: Tyler Beaumont — t.beaumont@cascadia-freight.com — (503) 555-0174

        Driver: Horacio Villanueva-Cruz
        Driver ID: CDL-OR-HV2209 | SSN on file: 541-88-2213
        Phone: (971) 555-0162

        Vehicle: 2021 Freightliner Cascadia — VIN 1FUJGLDR8MLMM1234 — Plate OR 44821T
        GPS: 45.5231°N, -122.6765°W (Portland, OR) — 2024-11-18 14:23 UTC
        Route: Portland → Sacramento (Manifest #CSF-44109)

        Issue: HOS violation — driver logged 11.5 hrs driving (legal max 11 hrs)
        Action: Schedule mandatory 10-hr rest; notify DOT compliance officer
        Emergency contact: Rosa Villanueva (wife) — (971) 555-0188
        """
    ]

    private func loadSampleText() {
        inputText = Self.sampleTexts.randomElement() ?? Self.sampleTexts[0]
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
        if value <= 20 { return .red }
        if value <= 70 { return .orange }
        return .green
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
        TokenMappingStore.shared.rehydrate(pastedText)
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
                        tokenCount = TokenMappingStore.shared.rehydrationCount(in: text)
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
    /// The stable UUID of the item being displayed. Using an ID instead of
    /// a `PIIItem` value means the view always reads the *live* item from
    /// `detector.detectedItems` — so retagging instantly reflects without a
    /// selectedToken / objectWillChange race condition.
    let itemId: UUID
    @ObservedObject var detector: PIIDetector
    @Binding var inputText: String
    @Binding var selectedToken: PIIItem?

    /// Controls the inline type-correction list. Using a pure-SwiftUI
    /// expanding list instead of a native NSMenu avoids the known issue
    /// where macOS menu-item clicks bleed through to the background overlay's
    /// tap-to-dismiss gesture.
    @State private var showingTypeSelector = false

    /// Always reads the live, up-to-date item from the detector.
    private var item: PIIItem? {
        detector.detectedItems.first { $0.id == itemId }
    }

    var body: some View {
        if let item {
            dropdownContent(item: item)
        }
    }

    @ViewBuilder
    private func dropdownContent(item: PIIItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                            Text(item.token)
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        // Tappable type badge — expands an inline list below
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                showingTypeSelector.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.type.rawValue.uppercased())
                                    .font(.caption2.weight(.semibold))
                                Image(systemName: showingTypeSelector ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundColor(showingTypeSelector ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(showingTypeSelector
                                ? Color.secondary.opacity(0.22)
                                : Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Correct the detected type")
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

                // Inline type selector — expands without native OS menu
                if showingTypeSelector {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(PIIType.allCases, id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    showingTypeSelector = false
                                }
                                retagAs(type)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type == item.type ? "checkmark" : "circle")
                                        .font(.system(size: 10, weight: type == item.type ? .bold : .regular))
                                        .foregroundColor(type == item.type ? .blue : .secondary)
                                        .frame(width: 14)
                                    Text(type.rawValue)
                                        .font(.system(size: 12))
                                        .foregroundColor(type == item.type ? .blue : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(type == item.type
                                    ? Color.blue.opacity(0.1)
                                    : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

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
        guard let item = item else { return }
        detector.applySelectedAlternative(alternative, forItemId: item.id, originalText: inputText)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { selectedToken = nil }
    }

    private func restoreOriginal() {
        guard let item = item else { return }
        detector.removeItem(item, originalText: inputText)
        selectedToken = nil
    }

    /// Change the item's type and regenerate alternatives.
    /// No selectedToken update is needed — the dropdown reads the live item
    /// from detector.detectedItems via the computed `item` property, so
    /// retagItem's objectWillChange immediately triggers a correct re-render.
    private func retagAs(_ newType: PIIType) {
        guard let item = item, newType != item.type else { return }
        detector.retagItem(item, as: newType, originalText: inputText)
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
