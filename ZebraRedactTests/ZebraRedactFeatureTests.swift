// ZebraRedactFeatureTests.swift
//
// Tests for PIIItem alternatives and PIIDetector scan behaviour.

import XCTest
@testable import ZebraRedact

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIIItem: alternatives
// ─────────────────────────────────────────────────────────────────────────────

final class PIIItemAlternativesTests: XCTestCase {

    // MARK: Completeness

    func testAllTypesHaveATokenAlternative() {
        for type in PIIType.allCases {
            let alts = PIIItem.generateAlternatives(for: type, original: "test")
            XCTAssertTrue(alts.contains { $0.strategy == .token },
                "\(type.rawValue) is missing a .token alternative")
        }
    }

    func testTokenAlternativeHasCorrectFormat() {
        for type in PIIType.allCases {
            let alts = PIIItem.generateAlternatives(for: type, original: "test")
            guard let tokenAlt = alts.first(where: { $0.strategy == .token }) else {
                XCTFail("\(type.rawValue) missing token alternative"); continue
            }
            XCTAssertTrue(tokenAlt.text.hasPrefix("[") && tokenAlt.text.hasSuffix("]"),
                "\(type.rawValue) token '\(tokenAlt.text)' must be wrapped in []")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIIDetector: scan behaviour
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

    // MARK: Token output format

    func testTokenModeProducesTokenFormatOutput() async {
        let detector = PIIDetector()
        detector.scan(text: "Send invoice to carol@payroll.com ASAP.")
        await waitForProcessing(detector)

        XCTAssertTrue(detector.redactedText.contains("[EMAIL_"),
            "Token mode must produce [EMAIL_XXXX] style replacement")
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
        detector.scan(text: text)
        await waitForProcessing(detector)

        guard let tagRange = text.range(of: "Project Phoenix") else {
            XCTFail("Precondition: 'Project Phoenix' must be in text"); return
        }
        try detector.addManualTag(range: tagRange, type: .custom, in: text)

        let manualItem = detector.detectedItems.first { $0.isManual }
        let manualId = try XCTUnwrap(manualItem?.id, "Manual item should exist")

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
        detector.scan(text: original)
        await waitForProcessing(detector)

        guard let customRange = original.range(of: "details") else {
            XCTFail("Precondition: 'details' must be in text"); return
        }
        try detector.addManualTag(range: customRange, type: .custom, in: original)

        let manualId = try XCTUnwrap(
            detector.detectedItems.first(where: { $0.isManual })?.id,
            "Manual item should exist after tagging 'details'")

        detector.scan(text: extended)
        await waitForProcessing(detector)

        XCTAssertTrue(detector.detectedItems.contains { $0.isManual },
            "Manual tag must survive re-scan when text is extended after the tag")
        XCTAssertTrue(detector.detectedItems.contains { $0.id == manualId },
            "UUID must be preserved when text is appended after the manual tag")
    }

    func testManualTagDroppedWhenOriginalTextDeleted() async throws {
        let original = "The project status update is pending review."
        let detector = PIIDetector()
        detector.scan(text: original)
        await waitForProcessing(detector)

        XCTAssertTrue(detector.detectedItems.isEmpty, "Precondition: clean text should have no auto-tags")

        guard let tagRange = original.range(of: "pending") else {
            XCTFail("Precondition: 'pending' must be in text"); return
        }
        try detector.addManualTag(range: tagRange, type: .custom, in: original)
        XCTAssertTrue(detector.detectedItems.contains { $0.isManual }, "Precondition")

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
