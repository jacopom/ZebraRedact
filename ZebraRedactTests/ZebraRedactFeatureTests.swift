// ZebraRedactFeatureTests.swift
//
// Tests for the three fixes shipped in the "new things to fix" cycle:
//   1. PIIItem — fake data variety (no more hardcoded "John Doe" / "user@example.com")
//   2. PIIDetector — LLM cache: remaskCurrentItems preserves items across mode switches
//   3. Cursor behaviour is UI-only and covered by manual verification notes at the bottom.
//
// To run:
//   Cmd+U in Xcode (test target ZebraRedactTests must be selected)
// OR
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcodebuild -project ZebraRedact.xcodeproj -target ZebraRedactTests test \
//     -destination 'platform=macOS'

import XCTest
@testable import ZebraRedact

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIIItem: fake data variety
// ─────────────────────────────────────────────────────────────────────────────

final class PIIItemFakeDataTests: XCTestCase {

    // Convenience: pull the semantic alternative text for a given type + original.
    private func semantic(for type: PIIType, original: String) -> String? {
        PIIItem.generateAlternatives(for: type, original: original)
            .first { $0.strategy == .semantic }?.text
    }

    // MARK: Names

    func testSemanticNamesAreDeterministic() {
        let original = "John Smith"
        let a = semantic(for: .name, original: original)
        let b = semantic(for: .name, original: original)
        XCTAssertEqual(a, b, "Same input must always produce the same fake name")
    }

    func testSemanticNamesAreVariedAcrossInputs() {
        let inputs = ["Alice Brown", "Bob Zhang", "Carol Davis", "David Müller",
                      "Eva Okafor", "Frank Chen", "Grace Kim"]
        let fakes = inputs.compactMap { semantic(for: .name, original: $0) }
        XCTAssertGreaterThan(Set(fakes).count, 1,
            "Different inputs must map to more than one distinct fake name")
    }

    func testSemanticNameIsNeverJohnDoe() {
        // Sample a wide spread of inputs — none should still return the old default
        let inputs = (0..<20).map { "Person \($0)" }
        for input in inputs {
            let fake = semantic(for: .name, original: input)
            XCTAssertNotEqual(fake, "John Doe",
                "'\(input)' still maps to hardcoded 'John Doe'")
        }
    }

    // MARK: Emails

    func testSemanticEmailsDeterministic() {
        let original = "alice@work.com"
        XCTAssertEqual(semantic(for: .email, original: original),
                       semantic(for: .email, original: original))
    }

    func testSemanticEmailsAreVaried() {
        let inputs = ["a@b.com", "c@d.net", "e@f.org", "g@h.io", "i@j.co", "k@l.edu"]
        let fakes = inputs.compactMap { semantic(for: .email, original: $0) }
        XCTAssertGreaterThan(Set(fakes).count, 1,
            "Different email inputs must produce more than one distinct fake email")
    }

    func testSemanticEmailIsNeverOldDefault() {
        let inputs = (0..<15).map { "user\($0)@test.com" }
        for input in inputs {
            let fake = semantic(for: .email, original: input)
            XCTAssertNotEqual(fake, "user@example.com",
                "'\(input)' still maps to hardcoded 'user@example.com'")
        }
    }

    // MARK: Phones

    func testSemanticPhonesAreVaried() {
        let inputs = ["+1 555 0001", "+44 20 0001", "+49 0002",
                      "+33 0003", "+81 0004", "+61 0005"]
        let fakes = inputs.compactMap { semantic(for: .phone, original: $0) }
        XCTAssertGreaterThan(Set(fakes).count, 1,
            "Phone fake data should vary across inputs")
    }

    func testSemanticPhoneIsNeverOldDefault() {
        let inputs = (0..<12).map { "555-00\(String(format: "%02d", $0))" }
        for input in inputs {
            let fake = semantic(for: .phone, original: input)
            XCTAssertNotEqual(fake, "(555) 123-4567",
                "'\(input)' still maps to hardcoded '(555) 123-4567'")
        }
    }

    // MARK: Addresses

    func testSemanticAddressesAreVaried() {
        let inputs = ["1 Alpha St", "2 Beta Ave", "3 Gamma Rd",
                      "4 Delta Blvd", "5 Epsilon Dr", "6 Zeta Way"]
        let fakes = inputs.compactMap { semantic(for: .address, original: $0) }
        XCTAssertGreaterThan(Set(fakes).count, 1,
            "Address fake data should vary across inputs")
    }

    func testSemanticAddressIsNever123MainSt() {
        let inputs = (0..<12).map { "\($0) Test Road" }
        for input in inputs {
            let fake = semantic(for: .address, original: input)
            XCTAssertNotEqual(fake, "123 Main St",
                "'\(input)' still maps to hardcoded '123 Main St'")
        }
    }

    // MARK: IP addresses

    func testSemanticIPsAreVaried() {
        let inputs = ["1.1.1.1", "2.2.2.2", "3.3.3.3", "4.4.4.4", "5.5.5.5", "6.6.6.6"]
        let fakes = inputs.compactMap { semantic(for: .ipAddress, original: $0) }
        XCTAssertGreaterThan(Set(fakes).count, 1,
            "IP fake data should vary across inputs")
    }

    // MARK: Completeness

    func testAllTypesHaveATokenAlternative() {
        for type in PIIType.allCases {
            let alts = PIIItem.generateAlternatives(for: type, original: "test")
            XCTAssertTrue(alts.contains { $0.strategy == .token },
                "\(type.rawValue) is missing a .token alternative")
        }
    }

    func testTypesExpectedToHaveSemanticActuallyDo() {
        let expected: [PIIType] = [.name, .email, .phone, .ipAddress, .address]
        for type in expected {
            let alts = PIIItem.generateAlternatives(for: type, original: "test")
            XCTAssertTrue(alts.contains { $0.strategy == .semantic },
                "\(type.rawValue) is missing a .semantic alternative")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIIDetector: scan behaviour & LLM cache
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PIIDetectorTests: XCTestCase {

    /// Poll until `isProcessing` drops to false, then yield once more so published
    /// property updates propagate to observers.
    private func waitForProcessing(_ detector: PIIDetector,
                                   timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while detector.isProcessing, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        }
        await Task.yield()
    }

    // MARK: Basic detection sanity

    func testEmailIsDetectedAndRedacted() async {
        let detector = PIIDetector()
        let text = "Please reach alice.jones@company.com for details."
        detector.scan(text: text)
        await waitForProcessing(detector)

        XCTAssertFalse(detector.detectedItems.isEmpty)
        XCTAssertTrue(detector.detectedItems.contains { $0.type == .email })
        XCTAssertFalse(detector.redactedText.contains("alice.jones@company.com"),
            "Original email must not appear in redacted output")
    }

    func testCleanTextProducesNoDetections() async {
        let detector = PIIDetector()
        let text = "The project looks good. Let's ship it."
        detector.scan(text: text)
        await waitForProcessing(detector)

        XCTAssertTrue(detector.detectedItems.isEmpty,
            "Clean prose must not trigger PII detection")
        XCTAssertEqual(detector.redactedText, text,
            "Redacted text must equal input when nothing is redacted")
    }

    func testMultiplePIITypesDetectedInOneScan() async {
        let detector = PIIDetector()
        let text = "Email: bob@acme.com  SSN: 123-45-6789  Card: 4111-1111-1111-1111"
        detector.scan(text: text)
        await waitForProcessing(detector)

        XCTAssertGreaterThanOrEqual(detector.detectedItems.count, 2,
            "Should detect at least email + one other PII type")
    }

    // MARK: Token vs semantic output format

    func testTokenModeProducesTokenFormatOutput() async {
        let detector = PIIDetector()
        detector.redactionMode = .token
        detector.scan(text: "Send invoice to carol@payroll.com ASAP.")
        await waitForProcessing(detector)

        XCTAssertTrue(detector.redactedText.contains("[EMAIL_"),
            "Token mode must produce [EMAIL_XXXX] style replacement")
    }

    func testSemanticModeProducesFakeOutput() async {
        let detector = PIIDetector()
        detector.redactionMode = .semantic
        detector.scan(text: "Send invoice to carol@payroll.com ASAP.")
        await waitForProcessing(detector)

        XCTAssertFalse(detector.redactedText.contains("carol@payroll.com"),
            "Original email must not appear in semantic output")
        XCTAssertFalse(detector.redactedText.contains("[EMAIL_"),
            "Semantic mode must not produce token-style output")
    }

    // MARK: LLM cache / remaskCurrentItems

    func testRemaskCurrentItemsPreservesItemCount() async {
        let detector = PIIDetector()
        let text = "Email john.smith@acme.com or call (555) 867-5309."
        detector.scan(text: text)
        await waitForProcessing(detector)

        let countAfterScan = detector.detectedItems.count
        guard countAfterScan > 0 else {
            XCTFail("Precondition: scan should detect at least one item"); return
        }

        // Switch mode and remask — items should be identical
        detector.redactionMode = .token
        detector.remaskCurrentItems(originalText: text)
        await waitForProcessing(detector)

        XCTAssertEqual(detector.detectedItems.count, countAfterScan,
            "remaskCurrentItems must not add or remove detected items")
    }

    func testModeSwitchChangesRedactedTextFormat() async {
        let detector = PIIDetector()
        let text = "Reply to dan@example.org when ready."

        detector.redactionMode = .token
        detector.scan(text: text)
        await waitForProcessing(detector)
        let tokenOutput = detector.redactedText

        detector.redactionMode = .semantic
        detector.remaskCurrentItems(originalText: text)
        await waitForProcessing(detector)
        let semanticOutput = detector.redactedText

        XCTAssertNotEqual(tokenOutput, semanticOutput,
            "Switching mode must change the redacted text")
        XCTAssertTrue(tokenOutput.contains("[EMAIL_"),
            "Token output must contain [EMAIL_XXXX] marker")
        XCTAssertFalse(semanticOutput.contains("[EMAIL_"),
            "Semantic output must not contain [EMAIL_XXXX] marker")
    }

    func testRemaskDoesNotRedetectWhenSwitchingModes() async {
        let detector = PIIDetector()
        let text = "Email frank@test.io or call 212-555-0134."
        detector.scan(text: text)
        await waitForProcessing(detector)

        let itemIDs = Set(detector.detectedItems.map(\.id))

        // Flip modes back and forth
        for mode: RedactionMode in [.token, .semantic, .token, .semantic] {
            detector.redactionMode = mode
            detector.remaskCurrentItems(originalText: text)
            await waitForProcessing(detector)
        }

        let finalIDs = Set(detector.detectedItems.map(\.id))
        XCTAssertEqual(itemIDs, finalIDs,
            "Item UUIDs must be stable across remask calls — no re-detection occurred")
    }

    func testNewScanClearsPreviousDetections() async {
        let detector = PIIDetector()
        detector.scan(text: "Email: alice@test.com, SSN: 123-45-6789")
        await waitForProcessing(detector)
        XCTAssertGreaterThan(detector.detectedItems.count, 0, "Precondition")

        detector.scan(text: "The sky is blue today.")
        await waitForProcessing(detector)

        XCTAssertEqual(detector.detectedItems.count, 0,
            "Scanning clean text must clear all previously detected items")
    }

    // MARK: appliedReplacements consistency

    func testAppliedReplacementsCoversAllMaskedItems() async {
        let detector = PIIDetector()
        detector.scan(text: "Contact grace@ops.io for the monthly report.")
        await waitForProcessing(detector)

        for item in detector.detectedItems where item.isMasked {
            XCTAssertNotNil(detector.appliedReplacements[item.id],
                "\(item.type.rawValue) item is masked but has no appliedReplacement entry")
        }
    }

    func testAppliedReplacementTokenAppearsInRedactedText() async {
        let detector = PIIDetector()
        detector.redactionMode = .token
        detector.scan(text: "Ping hugo@devteam.com for access.")
        await waitForProcessing(detector)

        for (_, replacement) in detector.appliedReplacements {
            XCTAssertTrue(detector.redactedText.contains(replacement),
                "Applied replacement '\(replacement)' must appear in redactedText")
        }
    }

    // MARK: - Manual tag preservation across re-scans

    func testManualTagSurvivesReScanWhenTextUnchanged() async throws {
        let text = "Please call Project Phoenix about the budget."
        let detector = PIIDetector()
        detector.redactionMode = .token
        detector.scan(text: text)
        await waitForProcessing(detector)

        // Manually tag "Project Phoenix"
        guard let tagRange = text.range(of: "Project Phoenix") else {
            XCTFail("Precondition: 'Project Phoenix' must be in text"); return
        }
        try detector.addManualTag(range: tagRange, type: .custom, in: text)

        let manualItem = detector.detectedItems.first { $0.isManual }
        let manualId = try XCTUnwrap(manualItem?.id, "Manual item should exist")

        // Re-scan the identical text (simulates user typing a character elsewhere)
        detector.scan(text: text)
        await waitForProcessing(detector)

        XCTAssertTrue(detector.detectedItems.contains { $0.isManual },
            "Manual tag must survive a re-scan of the same text")
        XCTAssertTrue(detector.detectedItems.contains { $0.id == manualId },
            "Manual tag UUID must be preserved across re-scan (appliedReplacements key stability)")
        XCTAssertNotNil(detector.appliedReplacements[manualId],
            "appliedReplacements entry must survive re-scan via UUID preservation")
    }

    func testManualTagSurvivesReScanWithAppendedText() async throws {
        let original = "Contact at alice@corp.com for details."
        let extended = original + " Updated: added more context here."
        let detector = PIIDetector()
        detector.redactionMode = .token
        detector.scan(text: original)
        await waitForProcessing(detector)

        // Add manual tag "alice@corp.com" — but NLTagger + regex already detect it,
        // so tag something that auto-detection won't pick up ("Contact" as custom PII).
        guard let tagRange = original.range(of: "alice@corp.com") else {
            XCTFail("Precondition: email must be in text"); return
        }
        // The email is already auto-detected; use the word "details" as a custom tag.
        guard let customRange = original.range(of: "details") else {
            XCTFail("Precondition: 'details' must be in text"); return
        }
        try detector.addManualTag(range: customRange, type: .custom, in: original)

        let manualId = try XCTUnwrap(
            detector.detectedItems.first(where: { $0.isManual })?.id,
            "Manual item should exist after tagging 'details'")

        // Re-scan the extended text (user typed more at the end)
        detector.scan(text: extended)
        await waitForProcessing(detector)

        XCTAssertTrue(detector.detectedItems.contains { $0.isManual },
            "Manual tag must survive re-scan when text is extended after the tag")
        XCTAssertTrue(detector.detectedItems.contains { $0.id == manualId },
            "UUID must be preserved when text is appended after the manual tag")
    }

    func testManualTagDroppedWhenOriginalTextDeleted() async throws {
        // Use text with no auto-detected PII so the manual range doesn't overlap
        let original = "The project status update is pending review."
        let detector = PIIDetector()
        detector.redactionMode = .token
        detector.scan(text: original)
        await waitForProcessing(detector)

        // Confirm no auto-detection (so "pending" is taggable without overlap)
        XCTAssertTrue(detector.detectedItems.isEmpty, "Precondition: clean text should have no auto-tags")

        guard let tagRange = original.range(of: "pending") else {
            XCTFail("Precondition: 'pending' must be in text"); return
        }
        try detector.addManualTag(range: tagRange, type: .custom, in: original)
        XCTAssertTrue(detector.detectedItems.contains { $0.isManual }, "Precondition")

        // Re-scan after the tagged word is removed
        let modified = "The project status update is under review."
        detector.scan(text: modified)
        await waitForProcessing(detector)

        XCTAssertFalse(detector.detectedItems.contains { $0.isManual },
            "Manual tag must be dropped when its original text no longer exists in the new input")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Cursor fix (manual verification guide)
// ─────────────────────────────────────────────────────────────────────────────
//
// The I-beam → arrow cursor fix in AlternativesDropdown cannot be automated
// (NSCursor state is not observable from tests). Verify manually:
//
//  1. Launch the app and paste: "Hi, call me at 415-555-0192"
//  2. Click the phone token in the output panel → AlternativesDropdown opens
//  3. Move the mouse over each alternative row
//     EXPECTED: arrow cursor throughout (no I-beam flash)
//  4. Move cursor off the dropdown → cursor returns to I-beam over the text view
//     EXPECTED: cursor reverts normally
//
