// SemanticRedactorTests.swift
//
// To run these tests:
//   In Xcode → File → New → Target → macOS Unit Testing Bundle
//   Name it "ZebraRedactTests", set Host Application to ZebraRedact
//   Then drag this file into the new test target.
//
// Or from the command line (after adding the test target to pbxproj):
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcodebuild -project ZebraRedact.xcodeproj -scheme ZebraRedact test

import XCTest
@testable import ZebraRedact

final class SemanticRedactorTests: XCTestCase {

    // MARK: - Test 1: Metric + Project (Primary Example)

    func testProjectMetric() async throws {
        let input = """
        In Q3 2024, Project Zebra delivered 7% growth in MRR for our top 10 enterprise customers compared to Q2 2023.
        """
        let request = RedactionRequest(
            text: input,
            taskDescription: "Summarize performance trends by project.",
            config: .withModel
        )
        let impl = SemanticRedactorImpl(llmClient: MockLLMClient.test1Client)
        let result = try await impl.analyzeAndRedact(request)

        // Verify key spans are detected
        let originals = result.spans.map(\.original)
        XCTAssertTrue(originals.contains("Q3 2024"), "Should detect Q3 2024 as a date")
        XCTAssertTrue(originals.contains("Project Zebra"), "Should detect Project Zebra as a project")
        XCTAssertTrue(originals.contains("7%"), "Should detect 7% as a metric")
        XCTAssertTrue(originals.contains("top 10 enterprise customers"), "Should detect customer group (via LLM)")
        XCTAssertTrue(originals.contains("Q2 2023"), "Should detect Q2 2023 as a date")

        // Verify placeholders
        let q3Span = result.spans.first { $0.original == "Q3 2024" }!
        XCTAssertEqual(q3Span.category, .date)
        XCTAssertEqual(q3Span.placeholder, "[QUARTER_1]")
        XCTAssertEqual(q3Span.semanticReplacement, "a recent quarter")

        let projectSpan = result.spans.first { $0.original == "Project Zebra" }!
        XCTAssertEqual(projectSpan.category, .project)
        XCTAssertEqual(projectSpan.placeholder, "[PROJECT_1]")
        XCTAssertNil(projectSpan.semanticReplacement, "Projects should use placeholder only")

        let metricSpan = result.spans.first { $0.original == "7%" }!
        XCTAssertEqual(metricSpan.category, .metric)
        XCTAssertEqual(metricSpan.placeholder, "[METRIC_1]")
        XCTAssertEqual(metricSpan.semanticReplacement, "single-digit growth")

        let customerSpan = result.spans.first { $0.original == "top 10 enterprise customers" }!
        XCTAssertEqual(customerSpan.category, .customerGroup)
        XCTAssertEqual(customerSpan.semanticReplacement, "a set of key enterprise customers")

        let q2Span = result.spans.first { $0.original == "Q2 2023" }!
        XCTAssertEqual(q2Span.category, .date)
        XCTAssertEqual(q2Span.placeholder, "[QUARTER_2]")
        XCTAssertEqual(q2Span.semanticReplacement, "the previous period")

        // Verify output text
        let expected = "In a recent quarter, [PROJECT_1] delivered single-digit growth in MRR for a set of key enterprise customers compared to the previous period."
        XCTAssertEqual(result.redactedText.trimmingCharacters(in: .whitespacesAndNewlines), expected)

        // Verify scores
        XCTAssertGreaterThanOrEqual(result.scores.overall, 70,
            "Qualitative replacements should keep overall score high")
    }

    // MARK: - Test 2: People + Decision

    func testPeopleDecision() async throws {
        let input = """
        Sarah Chen (Head of Sales) and Miguel Torres (VP, Product) agreed that we should sunset Project Atlas for our LATAM customers in H1 2025.
        """
        let request = RedactionRequest(
            text: input,
            taskDescription: nil,
            config: .withModel
        )
        let impl = SemanticRedactorImpl(llmClient: MockLLMClient.test2Client)
        let result = try await impl.analyzeAndRedact(request)

        let originals = result.spans.map(\.original)
        XCTAssertTrue(originals.contains("Sarah Chen") || originals.contains("Sarah"), "Should detect person name")
        XCTAssertTrue(originals.contains("Miguel Torres") || originals.contains("Miguel"), "Should detect person name")
        XCTAssertTrue(originals.contains("Project Atlas"), "Should detect project")
        XCTAssertTrue(originals.contains("LATAM customers"), "Should detect customer group via LLM")
        XCTAssertTrue(originals.contains("H1 2025"), "Should detect half-year date")

        // Project placeholder
        let atlasSpan = result.spans.first { $0.original == "Project Atlas" }!
        XCTAssertEqual(atlasSpan.category, .project)
        XCTAssertNil(atlasSpan.semanticReplacement)

        // Customer group replacement
        let latamSpan = result.spans.first { $0.original == "LATAM customers" }!
        XCTAssertEqual(latamSpan.semanticReplacement, "a regional customer segment")

        // Half-year date replacement
        let h1Span = result.spans.first { $0.original == "H1 2025" }!
        XCTAssertEqual(h1Span.category, .date)
        XCTAssertEqual(h1Span.semanticReplacement, "a recent half-year period")

        // Redacted text should not contain real names
        XCTAssertFalse(result.redactedText.contains("Sarah Chen"), "Real name should be redacted")
        XCTAssertFalse(result.redactedText.contains("Miguel Torres"), "Real name should be redacted")
        XCTAssertFalse(result.redactedText.contains("Project Atlas"), "Project name should be redacted")
        XCTAssertFalse(result.redactedText.contains("LATAM"), "Customer segment should be redacted")
    }

    // MARK: - Test 3: Over-Redaction Avoidance

    func testOutageExample() async throws {
        let input = """
        We saw 3 outages in January, all caused by configuration drift in our staging environment, not production.
        """
        let request = RedactionRequest(
            text: input,
            taskDescription: nil,
            config: .withModel
        )
        let impl = SemanticRedactorImpl(llmClient: MockLLMClient.test3Client)
        let result = try await impl.analyzeAndRedact(request)

        let originals = result.spans.map(\.original)
        XCTAssertTrue(originals.contains("3"), "Should detect small integer")
        XCTAssertTrue(originals.contains("January"), "Should detect standalone month")
        XCTAssertTrue(originals.contains("staging environment"), "Should detect via LLM")
        XCTAssertTrue(originals.contains("production"), "Should detect via LLM")

        // "3" → qualitative quantity
        let countSpan = result.spans.first { $0.original == "3" }!
        XCTAssertEqual(countSpan.semanticReplacement, "several")

        // "January" → recent month
        let monthSpan = result.spans.first { $0.original == "January" }!
        XCTAssertEqual(monthSpan.semanticReplacement, "a recent month")

        // Environment → qualitative (via mock)
        let stagingSpan = result.spans.first { $0.original == "staging environment" }!
        XCTAssertEqual(stagingSpan.semanticReplacement, "a non-production environment")

        let expected = "We saw several outages in a recent month, all caused by configuration drift in a non-production environment, not the live system."
        XCTAssertEqual(result.redactedText.trimmingCharacters(in: .whitespacesAndNewlines), expected)
    }

    // MARK: - Unit Tests: SemanticSynthesizer

    func testMetricReplacements() {
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("7%"), "single-digit growth")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("15%"), "low double-digit growth")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("35%"), "double-digit growth")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("80%"), "strong growth")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("3"), "several")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("1"), "one")
        XCTAssertEqual(SemanticSynthesizer.metricReplacement("$1.2M"), "millions in revenue")
    }

    func testDateReplacements() {
        XCTAssertEqual(SemanticSynthesizer.dateReplacement("Q3 2024", spanIndex: 0), "a recent quarter")
        XCTAssertEqual(SemanticSynthesizer.dateReplacement("Q2 2023", spanIndex: 1), "the previous period")
        XCTAssertEqual(SemanticSynthesizer.dateReplacement("H1 2025", spanIndex: 0), "a recent half-year period")
        XCTAssertEqual(SemanticSynthesizer.dateReplacement("January", spanIndex: 0), "a recent month")
    }

    // MARK: - Unit Tests: PatternDetector

    func testPatternDetectorDetectsEmail() {
        let detector = PatternDetector()
        let spans = detector.detect(in: "Contact us at hello@example.com for info.")
        XCTAssertTrue(spans.contains { $0.category == .email && $0.original == "hello@example.com" })
    }

    func testPatternDetectorDetectsMetricAndDate() {
        let detector = PatternDetector()
        let spans = detector.detect(in: "Revenue grew 7% in Q3 2024.")
        XCTAssertTrue(spans.contains { $0.original == "7%" && $0.category == .metric })
        XCTAssertTrue(spans.contains { $0.original == "Q3 2024" && $0.category == .date })
    }

    func testPatternDetectorDetectsProject() {
        let detector = PatternDetector()
        let spans = detector.detect(in: "Project Zebra is on track for Q4.")
        XCTAssertTrue(spans.contains { $0.original == "Project Zebra" && $0.category == .project })
    }

    func testNoModelUsesRulesOnly() async throws {
        let input = "Revenue grew 7% in Q3 2024 thanks to Project Alpha."
        let request = RedactionRequest(text: input, config: .standard)
        let impl = SemanticRedactorImpl(llmClient: NullLLMClient())
        let result = try await impl.analyzeAndRedact(request)

        // Must produce output without crashing, rules handle .metric / .date / .project
        XCTAssertFalse(result.redactedText.contains("7%"), "Metric should be redacted")
        XCTAssertFalse(result.redactedText.contains("Q3 2024"), "Date should be redacted")
        XCTAssertFalse(result.redactedText.contains("Project Alpha"), "Project should be redacted")
        XCTAssertTrue(result.redactedText.contains("single-digit growth"), "Metric gets qualitative replacement")
        XCTAssertTrue(result.redactedText.contains("a recent quarter"), "Date gets qualitative replacement")
    }
}
