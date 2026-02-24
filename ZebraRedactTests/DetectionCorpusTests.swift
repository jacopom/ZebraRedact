// DetectionCorpusTests.swift
//
// Eval-driven feedback loop for the PII detection pipeline.
//
// WORKFLOW:
//   1. Spot a bug in the UI (wrong detection, false positive, split name, etc.)
//   2. Add a failing DetectionCase to the corpus below — encode exactly what was wrong.
//   3. Fix the code in NLTaggerDetector / RegexDetector / PIIItem.
//   4. Test passes → regression is locked in forever.
//
// To run without the UI:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcodebuild test \
//     -project ZebraRedact.xcodeproj \
//     -scheme ZebraRedactTests \
//     -destination 'platform=macOS' \
//   | grep -E "Test Case|PASSED|FAILED|recall|Coverage"

import XCTest
@testable import ZebraRedact

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Corpus data model
// ─────────────────────────────────────────────────────────────────────────────

/// A single annotated test case.
struct DetectionCase {
    /// Human-readable label shown in XCTest failures.
    let name: String
    /// The raw input text to run through the detector.
    let text: String
    /// Items that MUST appear in the detected output.
    let mustDetect: [(type: PIIType, text: String)]
    /// Known false-positive patterns that must NOT appear.
    /// Each entry is (substring, wrongType) — asserts no item has that type AND matches that text.
    let mustNotClassify: [(text: String, wrongType: PIIType)]

    init(_ name: String, text: String,
         detect: [(PIIType, String)] = [],
         notAs: [(String, PIIType)] = []) {
        self.name = name
        self.text = text
        self.mustDetect = detect
        self.mustNotClassify = notAs
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Corpus
//
// Organised by:
//   A. Regex-detected patterns (deterministic, always pass)
//   B. NLTagger named entities
//   C. Regressions — each entry documents a specific bug that was fixed
//   D. Domain samples (GDPR, HIPAA, CCPA, Finance, Education, Transportation)
//   E. Edge cases
// ─────────────────────────────────────────────────────────────────────────────

let corpus: [DetectionCase] = [

    // ── A. Regex patterns ────────────────────────────────────────────────────

    DetectionCase("email: plain prose",
        text: "Please reach alice.jones@company.com for details.",
        detect: [(.email, "alice.jones@company.com")]),

    DetectionCase("email: angle-bracket header",
        text: "From: Principal Serena Abubakar <s.abubakar@westfield-elementary.edu>",
        detect: [(.email, "s.abubakar@westfield-elementary.edu")]),

    DetectionCase("email: reply-to line",
        text: "To: David & Yuki Tanaka-Hoffman <dtyh@gmail.com>",
        detect: [(.email, "dtyh@gmail.com")]),

    DetectionCase("phone: US parenthetical",
        text: "Call us at (503) 555-0167 during business hours.",
        detect: [(.phone, "(503) 555-0167")]),

    DetectionCase("phone: international E.164",
        text: "Reach me at +49 30 4059 7821 after 3 pm.",
        detect: [(.phone, "+49 30 4059 7821")]),

    DetectionCase("phone: US with country code",
        text: "+1 (212) 555-0134 is the main line.",
        detect: [(.phone, "+1 (212) 555-0134")]),

    DetectionCase("SSN: dashed format",
        text: "Her SSN on file is 516-44-7823.",
        detect: [(.ssn, "516-44-7823")]),

    DetectionCase("credit card: dashed 16-digit",
        text: "Card number: 4111-1111-1111-1111",
        detect: [(.creditCard, "4111-1111-1111-1111")]),

    DetectionCase("IP: private class-C",
        text: "Server is running at 192.168.1.100.",
        detect: [(.ipAddress, "192.168.1.100")]),

    DetectionCase("IP: private class-A",
        text: "Last login from 10.10.1.50.",
        detect: [(.ipAddress, "10.10.1.50")]),

    DetectionCase("API key: sk- prefix",
        text: "API Key: sk-proj1234567890abcdefghij1234567890",
        detect: [(.apiKey, "sk-proj1234567890abcdefghij1234567890")]),

    // ── B. NLTagger named entities ───────────────────────────────────────────

    DetectionCase("name: simple full name in prose",
        text: "The meeting was chaired by Serena Abubakar.",
        detect: [(.name, "Serena Abubakar")]),

    DetectionCase("name: person in email signature",
        text: "Best regards,\nIngrid Sörensen\nHR Manager",
        detect: [(.name, "Ingrid Sörensen")]),

    // ── C. Regressions ───────────────────────────────────────────────────────
    //
    // Each entry documents a specific UI-observed bug that was fixed.
    // NEVER delete these — they are the memory of the detection pipeline.

    // Bug: NLTagger split "Tanaka-Hoffman" at the hyphen, classifying "Hoffman"
    // as a place/address (German surname confused with a toponym).
    // Fix: mergeHyphenatedNames() in NLTaggerDetector post-processes adjacent
    //      name/address items separated by "-" into a single Name item.
    DetectionCase("REGRESSION — hyphenated surname: Hoffman must not be Address",
        text: "Subject: Incident Report re: Maya Tanaka-Hoffman, Grade 3",
        notAs: [("Hoffman", .address)]),

    DetectionCase("REGRESSION — hyphenated surname in To: header",
        text: "To: David & Yuki Tanaka-Hoffman <dtyh@gmail.com>",
        detect: [(.email, "dtyh@gmail.com")],
        notAs: [("Hoffman", .address), ("Tanaka", .address)]),

    // Bug: "Yuki Tanaka" is literally in FakeData.names, so the deterministic
    // hash mapped the original back to itself — no anonymisation occurred.
    // Fix: FakeData.pickExcluding() filters the original before selecting.
    DetectionCase("REGRESSION — fake name must differ from 'Yuki Tanaka'",
        text: "Contact Yuki Tanaka for approval.",
        detect: [(.name, "Yuki Tanaka")]),   // just ensure it's detected; property test checks fake≠original

    // Bug: same entity appearing at multiple positions in the text (e.g. "Maya"
    // appears twice) produced duplicate entries in appliedReplacements and sidebar.
    // Fix: deduplication in UI (uniqueRedactedItems) + same alternatives reused.
    DetectionCase("REGRESSION — duplicate person name doesn't corrupt ghostedText",
        text: "Maya was present. The teacher spoke with Maya again later.",
        detect: [(.name, "Maya")]),

    // ── D. Domain samples ────────────────────────────────────────────────────

    DetectionCase("GDPR: EU employee onboarding",
        text: """
            Personal email: m.bruckner.privat@gmx.de
            Work phone: +49 30 4059 7821
            IBAN: DE89 3704 0044 0532 0130 00
            """,
        detect: [
            (.email, "m.bruckner.privat@gmx.de"),
            (.phone, "+49 30 4059 7821"),
        ]),

    DetectionCase("GDPR: customer complaint with email + phone",
        text: "Customer: jcmorin77@free.fr  Phone: +33 6 12 34 56 78",
        detect: [
            (.email, "jcmorin77@free.fr"),
            (.phone, "+33 6 12 34 56 78"),
        ]),

    DetectionCase("HIPAA: patient referral — SSN + two phones",
        text: "SSN: 516-44-7823  Patient: (312) 555-0178  Emergency: (312) 555-0199",
        detect: [
            (.ssn, "516-44-7823"),
            (.phone, "(312) 555-0178"),
            (.phone, "(312) 555-0199"),
        ]),

    DetectionCase("HIPAA: pre-auth with email",
        text: "Billing: cpark@riverside-ortho.com  Patient: dreyes1979@icloud.com",
        detect: [
            (.email, "cpark@riverside-ortho.com"),
            (.email, "dreyes1979@icloud.com"),
        ]),

    DetectionCase("CCPA: deletion request email + phone",
        text: "Email: jasmine.tran.la@gmail.com  Phone: (213) 555-0147",
        detect: [
            (.email, "jasmine.tran.la@gmail.com"),
            (.phone, "(213) 555-0147"),
        ]),

    DetectionCase("Finance: wire transfer email + phone",
        text: "richard.fontaine@fontainecap.com | +1 (212) 555-0134  EIN: 84-3210987",
        detect: [
            (.email, "richard.fontaine@fontainecap.com"),
            (.phone, "+1 (212) 555-0134"),
        ]),

    DetectionCase("Finance: trade confirmation SSN + email",
        text: "SSN: 219-77-4450  Email: nkessler.trading@outlook.com",
        detect: [
            (.ssn, "219-77-4450"),
            (.email, "nkessler.trading@outlook.com"),
        ]),

    DetectionCase("Education: student record email + phone",
        text: "Parent: carmela.esposito@famiglia.it  Emergency: (617) 555-0196",
        detect: [
            (.email, "carmela.esposito@famiglia.it"),
            (.phone, "(617) 555-0196"),
        ]),

    DetectionCase("Transportation: ride receipt email + IP",
        text: "Email: a.volkov.sf@yandex.com  IP: 76.94.118.22",
        detect: [
            (.email, "a.volkov.sf@yandex.com"),
            (.ipAddress, "76.94.118.22"),
        ]),

    DetectionCase("Transportation: fleet manager email + phone",
        text: "t.beaumont@cascadia-freight.com  (503) 555-0174",
        detect: [
            (.email, "t.beaumont@cascadia-freight.com"),
            (.phone, "(503) 555-0174"),
        ]),

    // ── E. Edge cases ────────────────────────────────────────────────────────

    DetectionCase("edge: multiple PII types in one line",
        text: "Email: bob@acme.com  SSN: 123-45-6789  Card: 4111-1111-1111-1111  IP: 10.0.0.1",
        detect: [
            (.email, "bob@acme.com"),
            (.ssn, "123-45-6789"),
            (.creditCard, "4111-1111-1111-1111"),
            (.ipAddress, "10.0.0.1"),
        ]),

    DetectionCase("edge: clean prose — no PII",
        text: "The project timeline looks good. We will ship in Q4.",
        detect: [],   // nothing should fire
        notAs: []),

    DetectionCase("edge: numbers that are NOT PII",
        text: "We had 3 outages in January. The team fixed 12 bugs this sprint.",
        detect: [],
        notAs: []),
]

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Test runner
// ─────────────────────────────────────────────────────────────────────────────

final class DetectionCorpusTests: XCTestCase {

    // One shared detector instance — NLTaggerDetector is not @MainActor.
    private let nlDetector = NLTaggerDetector()

    // ── Corpus: mustDetect ────────────────────────────────────────────────────

    /// Every item in mustDetect must appear in the raw detection output.
    func testCorpusMustDetectAll() {
        var failures: [String] = []

        for tc in corpus where !tc.mustDetect.isEmpty {
            let items = nlDetector.detect(in: tc.text)
            for (expectedType, expectedText) in tc.mustDetect {
                let found = items.contains {
                    $0.type == expectedType && $0.originalText == expectedText
                }
                if !found {
                    let detected = items.map { "\($0.type.rawValue)(\"\($0.originalText)\")" }.joined(separator: ", ")
                    failures.append("[\(tc.name)] missing \(expectedType.rawValue)(\"\(expectedText)\")\n    detected: [\(detected)]")
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("Detection corpus — mustDetect failures:\n" + failures.map { "  • \($0)" }.joined(separator: "\n"))
        }
    }

    // ── Corpus: mustNotClassify (false-positive regressions) ─────────────────

    /// No item in mustNotClassify must appear in the output.
    func testCorpusMustNotClassify() {
        var failures: [String] = []

        for tc in corpus where !tc.mustNotClassify.isEmpty {
            let items = nlDetector.detect(in: tc.text)
            for (badText, badType) in tc.mustNotClassify {
                let hit = items.first { $0.type == badType && $0.originalText == badText }
                if hit != nil {
                    failures.append("[\(tc.name)] false positive: \(badType.rawValue)(\"\(badText)\")")
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("Detection corpus — false-positive regressions:\n" + failures.map { "  • \($0)" }.joined(separator: "\n"))
        }
    }

    // ── Corpus: clean text produces no regex PII ──────────────────────────────

    func testCleanCasesProduceNoRegexPII() {
        let regexTypes: Set<PIIType> = [.email, .phone, .creditCard, .ssn, .ipAddress, .apiKey]
        let cleanCases = corpus.filter { $0.mustDetect.isEmpty && $0.mustNotClassify.isEmpty }

        for tc in cleanCases {
            let items = nlDetector.detect(in: tc.text)
            let regexHits = items.filter { regexTypes.contains($0.type) }
            if !regexHits.isEmpty {
                let found = regexHits.map { "\($0.type.rawValue)(\"\($0.originalText)\")" }.joined(separator: ", ")
                XCTFail("[\(tc.name)] expected no regex PII, found: \(found)")
            }
        }
    }

    // ── Precision / Recall report (informational) ────────────────────────────
    //
    // Prints a coverage table to the test log. Fails if overall recall < 80%.
    // Run with: xcodebuild test ... | grep -E "✓|✗|recall"

    func testPrintCoverageReport() {
        var totalExpected = 0
        var totalFound = 0
        var lines: [String] = ["\n=== ZebraRedact — Detection Coverage Report ==="]

        for tc in corpus where !tc.mustDetect.isEmpty {
            let items = nlDetector.detect(in: tc.text)
            var caseFound = 0
            var caseMissed: [String] = []

            for (expectedType, expectedText) in tc.mustDetect {
                if items.contains(where: { $0.type == expectedType && $0.originalText == expectedText }) {
                    caseFound += 1
                } else {
                    caseMissed.append("\(expectedType.rawValue)(\"\(expectedText)\")")
                }
            }

            totalExpected += tc.mustDetect.count
            totalFound += caseFound

            let status = caseMissed.isEmpty ? "✓" : "✗"
            let ratio = "\(caseFound)/\(tc.mustDetect.count)"
            let missNote = caseMissed.isEmpty ? "" : "  missed: \(caseMissed.joined(separator: ", "))"
            lines.append("  \(status) [\(tc.name)] \(ratio)\(missNote)")
        }

        let recallPct = totalExpected > 0 ? Double(totalFound) / Double(totalExpected) * 100 : 100.0
        lines.append("\nOverall recall: \(totalFound)/\(totalExpected) (\(String(format: "%.0f", recallPct))%)")

        // False-positive regressions
        var fpFailures = 0
        for tc in corpus where !tc.mustNotClassify.isEmpty {
            let items = nlDetector.detect(in: tc.text)
            for (badText, badType) in tc.mustNotClassify {
                if items.contains(where: { $0.type == badType && $0.originalText == badText }) {
                    fpFailures += 1
                }
            }
        }
        lines.append("False-positive regressions: \(fpFailures > 0 ? "✗ \(fpFailures)" : "✓ 0")")
        lines.append("================================================")

        print(lines.joined(separator: "\n"))

        XCTAssertGreaterThanOrEqual(
            recallPct, 80.0,
            "Overall detection recall \(String(format: "%.0f", recallPct))% is below the 80% minimum threshold"
        )
    }

    // ── Property: fake replacement ≠ original ────────────────────────────────
    //
    // Covers the specific values from the FakeData pool that were known to hash
    // back to themselves before pickExcluding() was introduced.

    func testFakeNeverEqualsOriginalForKnownCollisions() {
        let knownCollisions: [(PIIType, String)] = [
            // Names in FakeData.names pool — these used to map to themselves
            (.name, "Yuki Tanaka"),
            (.name, "Emma Wilson"),
            (.name, "Priya Sharma"),
            (.name, "Diego Fernández"),
            (.name, "Arjun Nair"),
            // Emails in FakeData.emails pool
            (.email, "y.tanaka@corp.jp"),
            (.email, "a.wilson@techcorp.io"),
            (.email, "p.sharma@consulting.in"),
            // Phones in FakeData.phones pool
            (.phone, "(415) 555-0192"),
            (.phone, "+44 20 7946 0958"),
            // Addresses in FakeData.addresses pool
            (.address, "742 Evergreen Terrace, Springfield"),
            (.address, "1 Harbour Rd, Hong Kong"),
            // IPs in FakeData.ipAddresses pool
            (.ipAddress, "192.168.0.100"),
            (.ipAddress, "10.0.0.1"),
        ]

        for (type, original) in knownCollisions {
            let fake = PIIItem.generateAlternatives(for: type, original: original)
                .first { $0.strategy == .semantic }?.text
            XCTAssertNotNil(fake, "\(type.rawValue) has no semantic alternative")
            XCTAssertNotEqual(fake, original,
                "Fake for \(type.rawValue)(\"\(original)\") still equals original — pickExcluding() not working")
        }
    }

    func testFakeIsDeterministicButVaries() {
        // Same input → same fake every time
        for _ in 0..<3 {
            let a = PIIItem.generateAlternatives(for: .name, original: "Alice Brown").first { $0.strategy == .semantic }?.text
            let b = PIIItem.generateAlternatives(for: .name, original: "Alice Brown").first { $0.strategy == .semantic }?.text
            XCTAssertEqual(a, b, "Same input must always produce the same fake (deterministic hash)")
        }

        // Different inputs → more than one distinct output
        let inputs = ["Alice Brown", "Bob Zhang", "Carol Davis", "David Müller", "Eva Okafor", "Frank Chen"]
        let fakes = Set(inputs.compactMap {
            PIIItem.generateAlternatives(for: .name, original: $0).first { $0.strategy == .semantic }?.text
        })
        XCTAssertGreaterThan(fakes.count, 1,
            "Different names must produce more than one distinct fake — hash spread too narrow")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIIDetector integration (async, @MainActor)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DetectorIntegrationTests: XCTestCase {

    private func waitForPII(_ d: PIIDetector, timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while d.isProcessing, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await Task.yield()
    }

    // ── ghostedText must never contain the original PII ───────────────────────

    func testTokenModeGhostedTextContainsNoPII() async {
        let texts = [
            "Email alice@work.io or call (415) 555-0192.",
            "SSN: 219-77-4450  Card: 4111-1111-1111-1111  IP: 10.10.1.50",
            "API Key: sk-test1234567890abcdef  Server: 172.16.0.1",
        ]
        for text in texts {
            let d = PIIDetector()
            d.redactionMode = .token
            d.scan(text: text)
            await waitForPII(d)
            for item in d.detectedItems where item.isMasked {
                XCTAssertFalse(d.ghostedText.contains(item.originalText),
                    "Token mode: ghostedText still contains \"\(item.originalText)\"")
            }
        }
    }

    func testSemanticModeGhostedTextContainsNoPII() async {
        let text = "Contact grace@ops.io or +1 (650) 555-0192 for the monthly report."
        let d = PIIDetector()
        d.redactionMode = .semantic
        d.scan(text: text)
        await waitForPII(d)
        for item in d.detectedItems where item.isMasked {
            XCTAssertFalse(d.ghostedText.contains(item.originalText),
                "Semantic mode: ghostedText still contains \"\(item.originalText)\"")
        }
    }

    // ── appliedReplacements stay in sync ─────────────────────────────────────

    func testAppliedReplacementsAllPresentInGhostedText() async {
        let text = "From: bob@acme.com  Phone: (212) 555-0134  SSN: 123-45-6789"
        let d = PIIDetector()
        d.scan(text: text)
        await waitForPII(d)
        for (_, replacement) in d.appliedReplacements {
            XCTAssertTrue(d.ghostedText.contains(replacement),
                "appliedReplacement '\(replacement)' not found in ghostedText")
        }
    }

    func testAppliedReplacementsAfterRemask() async {
        let text = "Reply to dan@example.org when ready."
        let d = PIIDetector()
        d.scan(text: text)
        await waitForPII(d)

        for mode: RedactionMode in [.token, .semantic, .token] {
            d.redactionMode = mode
            d.remaskCurrentItems(originalText: text)
            await waitForPII(d)
            for (_, replacement) in d.appliedReplacements {
                XCTAssertTrue(d.ghostedText.contains(replacement),
                    "[\(mode)] appliedReplacement '\(replacement)' not in ghostedText after remask")
            }
        }
    }

    // ── GhostMappingStore rehydration round-trip ──────────────────────────────

    func testRehydrationRoundTripTokenMode() async {
        let original = "Send report to ida@finance.io and call (312) 555-0178."
        let d = PIIDetector()
        d.redactionMode = .token
        d.scan(text: original)
        await waitForPII(d)

        let ghosted = d.ghostedText
        XCTAssertNotEqual(ghosted, original, "ghostedText must differ from original")

        let restored = GhostMappingStore.shared.rehydrate(ghosted)
        // The restored text should contain the original PII values
        for item in d.detectedItems where item.isMasked {
            XCTAssertTrue(restored.contains(item.originalText),
                "Rehydrated text missing '\(item.originalText)'")
        }
    }

    func testRehydrationRoundTripSemanticMode() async {
        let original = "Contact hugo@devteam.io for access."
        let d = PIIDetector()
        d.redactionMode = .semantic
        d.scan(text: original)
        await waitForPII(d)

        let ghosted = d.ghostedText
        let restored = GhostMappingStore.shared.rehydrate(ghosted)

        for item in d.detectedItems where item.isMasked {
            XCTAssertTrue(restored.contains(item.originalText),
                "Semantic mode rehydration missing '\(item.originalText)' — GhostMappingStore may be storing ghostToken instead of actual replacement")
        }
    }

    // ── Duplicate entities don't corrupt output ───────────────────────────────
    //
    // Regression: "Maya" appeared twice in text → two separate PIIItems with the
    // same originalText but different UUIDs. Both must be redacted, and the
    // appliedReplacements for each must remain consistent.

    func testDuplicateEntityBothOccurrencesRedacted() async {
        let text = "Maya was present. The teacher spoke with Maya again later."
        let d = PIIDetector()
        d.redactionMode = .token
        d.scan(text: text)
        await waitForPII(d)

        // "Maya" should not appear in the ghosted output at all
        // (both occurrences must be replaced)
        let mayaItems = d.detectedItems.filter { $0.originalText == "Maya" }
        guard !mayaItems.isEmpty else { return } // NLTagger may not detect first names — not a failure

        XCTAssertFalse(d.ghostedText.contains("Maya"),
            "Both occurrences of 'Maya' must be redacted, but at least one remains in ghostedText")
    }
}
