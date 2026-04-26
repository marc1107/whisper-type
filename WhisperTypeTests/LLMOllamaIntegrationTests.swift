import XCTest
@testable import WhisperType

/// Local-only integration tests against a running Ollama daemon.
///
/// These tests intentionally skip themselves when Ollama is not reachable on
/// `localhost:11434`, so they are safe to leave in the default test scheme:
/// CI (where Ollama is not installed) silently skips them, and they run
/// for real on a developer machine that has Ollama plus the model pulled.
///
/// They exercise the full LLM pipeline (prompt assembly → request → response
/// parsing → thinking-tag stripping) end-to-end with the real default prompt
/// shipped in `DefaultLLMPrompt.md`.
///
/// Because we run a small local model (default `gemma4:e2b`), individual
/// generations are non-deterministic. Each scenario is therefore retried N
/// times and considered successful if at least K runs satisfy the assertions
/// (`successesRequired` / `attempts`). 4-of-5 is the bar: forgiving enough to
/// tolerate the model occasionally ignoring the formatting instruction, strict
/// enough to catch genuine regressions in the prompt or transport layer.
final class LLMOllamaIntegrationTests: XCTestCase {

    private let ollamaModel = "gemma4:e2b"
    private let attempts = 5
    private let successesRequired = 4

    private let processor = LLMProcessor()

    // MARK: - Skip when Ollama is unreachable

    override func setUp() async throws {
        try await super.setUp()
        try await skipIfOllamaUnavailable()
        try await skipIfModelMissing(ollamaModel)
    }

    private func skipIfOllamaUnavailable() async throws {
        let url = URL(string: "http://localhost:11434/api/tags")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        let session = URLSession(configuration: config)
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw XCTSkip("Ollama not reachable on localhost:11434 — skipping integration tests")
            }
        } catch is XCTSkip {
            throw XCTSkip("Ollama not reachable on localhost:11434")
        } catch {
            throw XCTSkip("Ollama not reachable on localhost:11434 (\(error.localizedDescription))")
        }
    }

    private func skipIfModelMissing(_ model: String) async throws {
        let url = URL(string: "http://localhost:11434/api/tags")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        let session = URLSession(configuration: config)
        struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw XCTSkip("Ollama not reachable on localhost:11434 — skipping integration tests")
            }
            let tags = try JSONDecoder().decode(Tags.self, from: data)
            let names = tags.models.map { $0.name }
            guard names.contains(model) else {
                throw XCTSkip("Ollama model '\(model)' not pulled — run `ollama pull \(model)`")
            }
        } catch is XCTSkip {
            throw XCTSkip("Ollama not reachable on localhost:11434")
        } catch {
            throw XCTSkip("Ollama not reachable on localhost:11434 (\(error.localizedDescription))")
        }
    }

    // MARK: - Helpers

    private func makeContext(thinking: Bool) -> LLMRequestContext {
        LLMRequestContext(
            useDefaultPrompt: true,
            customPrompt: "",
            dictionary: [],
            thinkingEnabled: thinking,
            model: ollamaModel,
            provider: .ollama
        )
    }

    private struct Scenario {
        let name: String
        let input: String
        /// All predicates must hold for the run to count as a success.
        let predicates: [(String) -> Bool]
    }

    /// Runs `scenario` `attempts` times and asserts at least `successesRequired`
    /// runs satisfy every predicate. On failure, prints every output so the
    /// developer can diff the model's actual responses against expectations.
    private func runRepeatedly(_ scenario: Scenario, thinking: Bool) async {
        let context = makeContext(thinking: thinking)
        var successes = 0
        var transcripts: [String] = []

        for attempt in 1...attempts {
            do {
                let output = try await processor.process(text: scenario.input, context: context)
                transcripts.append("[\(attempt)/\(attempts)] \(output)")
                if scenario.predicates.allSatisfy({ $0(output) }) {
                    successes += 1
                }
            } catch {
                transcripts.append("[\(attempt)/\(attempts)] ERROR: \(error.localizedDescription)")
            }
        }

        XCTAssertGreaterThanOrEqual(
            successes,
            successesRequired,
            """
            Scenario '\(scenario.name)' (thinking=\(thinking)) only succeeded \(successes)/\(attempts) times.
            Required: \(successesRequired)/\(attempts).
            Outputs:
            \(transcripts.joined(separator: "\n----\n"))
            """
        )
    }

    // MARK: - Predicates (reusable)

    /// At least the markers `1.` and `2.` (and ideally `3.`) appear, each at
    /// the start of its own line — i.e. the model produced a numbered list,
    /// not an inline "1. foo, 2. bar" string.
    private static let producesNumberedList: (String) -> Bool = { output in
        let lines = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        let numberedLines = lines.filter { line in
            // Match "1.", "2.", "3." … at the start of the line.
            line.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }
        return numberedLines.count >= 2
    }

    /// Output contains real newline characters — guards against the model
    /// returning everything on a single line.
    private static let preservesNewlines: (String) -> Bool = { output in
        output.contains("\n")
    }

    /// At least two bullet markers (`-` or `•` or `*`) at line starts — used
    /// for the un-ordered enumeration scenario.
    private static let producesBulletList: (String) -> Bool = { output in
        let lines = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        let bulletLines = lines.filter { line in
            line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ")
        }
        return bulletLines.count >= 2
    }

    // MARK: - Scenarios

    private var germanNumberedList: Scenario {
        Scenario(
            name: "German 'erstens/zweitens/drittens' → numbered list",
            input: "Ich bestelle ein neues Feature. Es soll folgendes unterstützen. Erstens neues Design, zweitens Codefixes und drittens Aktualisierung der Readme.",
            predicates: [Self.producesNumberedList, Self.preservesNewlines]
        )
    }

    private var englishNumberedList: Scenario {
        Scenario(
            name: "English 'first/second/third' → numbered list",
            input: "I want you to implement the following three features. First a tracker for loading times. Second a notification when done and third a feature to give feedback to the developer.",
            predicates: [Self.producesNumberedList, Self.preservesNewlines]
        )
    }

    private var prosePassthrough: Scenario {
        Scenario(
            name: "Prose without enumeration markers stays prose",
            input: "I went to the store this morning and bought milk and eggs and some fresh bread.",
            // Should NOT contain a numbered list — exactly one predicate, the
            // negation of `producesNumberedList`. Newline preservation is not
            // applicable for a single-line input.
            predicates: [{ !Self.producesNumberedList($0) }]
        )
    }

    // MARK: - Tests: thinking ENABLED

    func testGermanNumberedListWithThinking() async {
        await runRepeatedly(germanNumberedList, thinking: true)
    }

    func testEnglishNumberedListWithThinking() async {
        await runRepeatedly(englishNumberedList, thinking: true)
    }

    func testProsePassthroughWithThinking() async {
        await runRepeatedly(prosePassthrough, thinking: true)
    }

    // MARK: - Tests: thinking DISABLED

    func testGermanNumberedListWithoutThinking() async {
        await runRepeatedly(germanNumberedList, thinking: false)
    }

    func testEnglishNumberedListWithoutThinking() async {
        await runRepeatedly(englishNumberedList, thinking: false)
    }

    func testProsePassthroughWithoutThinking() async {
        await runRepeatedly(prosePassthrough, thinking: false)
    }
}
