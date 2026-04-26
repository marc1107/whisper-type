import XCTest
@testable import WhisperType

final class KeychainHelperTests: XCTestCase {
    private let testKey = "test_whispertype_llm_key"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey)
    }

    func testSaveAndLoad() {
        KeychainHelper.save(key: testKey, value: "my-secret-key")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "my-secret-key")
    }

    func testOverwriteUpdatesValue() {
        KeychainHelper.save(key: testKey, value: "first")
        KeychainHelper.save(key: testKey, value: "second")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "second")
    }

    func testDeleteRemovesKey() {
        KeychainHelper.save(key: testKey, value: "value")
        KeychainHelper.delete(key: testKey)
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }

    func testLoadNonexistentKeyReturnsNil() {
        XCTAssertNil(KeychainHelper.load(key: "nonexistent_whispertype_key_xyz_abc"))
    }

    func testSaveEmptyStringAndLoad() {
        KeychainHelper.save(key: testKey, value: "")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "")
    }
}

final class DictionaryEntryTests: XCTestCase {
    func testCodingRoundTrip() throws {
        let entries = [
            DictionaryEntry(from: "aws", to: "AWS"),
            DictionaryEntry(from: "k8s", to: "Kubernetes"),
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        XCTAssertEqual(entries, decoded)
    }

    func testEmptyArrayRoundTrip() throws {
        let entries: [DictionaryEntry] = []
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }

    func testDefaultInitHasEmptyStrings() {
        let entry = DictionaryEntry()
        XCTAssertTrue(entry.from.isEmpty)
        XCTAssertTrue(entry.to.isEmpty)
    }
}

final class LLMPromptTests: XCTestCase {
    private let processor = LLMProcessor()

    func testDefaultPromptIncluded() {
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: true,
            customPrompt: "",
            entries: []
        )
        XCTAssertTrue(prompt.contains("transcription post-processor"))
    }

    func testDefaultPromptExcluded() {
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: []
        )
        XCTAssertFalse(prompt.contains("transcription post-processor"))
    }

    func testCustomPromptAppended() {
        let custom = "Always output in German."
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: custom,
            entries: []
        )
        XCTAssertEqual(prompt.trimmingCharacters(in: .whitespacesAndNewlines), custom)
    }

    func testCustomAndDefaultCombined() {
        let custom = "Extra instruction."
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: true,
            customPrompt: custom,
            entries: []
        )
        XCTAssertTrue(prompt.contains("transcription post-processor"))
        XCTAssertTrue(prompt.contains(custom))
    }

    func testDictionaryEntriesAppendedToPrompt() {
        let entries = [
            DictionaryEntry(from: "aws", to: "AWS"),
            DictionaryEntry(from: "k8s", to: "Kubernetes"),
        ]
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: entries
        )
        XCTAssertTrue(prompt.contains("aws → AWS"))
        XCTAssertTrue(prompt.contains("k8s → Kubernetes"))
        XCTAssertTrue(prompt.contains("Word corrections dictionary"))
    }

    func testEmptyEntriesFilteredOut() {
        let entries = [
            DictionaryEntry(from: "", to: "something"),
            DictionaryEntry(from: "valid", to: "Valid"),
        ]
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: entries
        )
        XCTAssertTrue(prompt.contains("valid → Valid"))
        XCTAssertFalse(prompt.contains(" → something"))
    }

    func testAllPartsEmpty() {
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: []
        )
        XCTAssertTrue(prompt.isEmpty)
    }

    func testWhitespaceOnlyCustomPromptIgnored() {
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "   \n  ",
            entries: []
        )
        XCTAssertTrue(prompt.isEmpty)
    }
}

final class LLMProviderTests: XCTestCase {
    func testOllamaDoesNotRequireAPIKey() {
        XCTAssertFalse(LLMProvider.ollama.requiresAPIKey)
    }

    func testOtherProvidersRequireAPIKey() {
        for provider in [LLMProvider.groq, .cerebras, .openRouter] {
            XCTAssertTrue(provider.requiresAPIKey, "\(provider) should require an API key")
        }
    }

    func testKeychainKeysAreUnique() {
        let keys = LLMProvider.allCases.map { $0.keychainKey }
        XCTAssertEqual(keys.count, Set(keys).count, "All keychain keys must be unique")
    }

    func testBaseURLsAreValid() {
        for provider in LLMProvider.allCases {
            XCTAssertNotNil(URL(string: provider.baseURL), "\(provider) baseURL should be a valid URL")
        }
    }
}

final class WhisperModelTests: XCTestCase {
    func testDistilMediumEnIsEnglishOnly() {
        XCTAssertTrue(WhisperModel.distilMediumEn.isEnglishOnly)
    }

    func testOtherModelsAreNotEnglishOnly() {
        let nonEnglishOnly = WhisperModel.allCases.filter { $0 != .distilMediumEn }
        for model in nonEnglishOnly {
            XCTAssertFalse(model.isEnglishOnly, "\(model) should not be English-only")
        }
    }

    func testAllModelsHaveUniqueRawValues() {
        let rawValues = WhisperModel.allCases.map { $0.rawValue }
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    func testDownloadURLsAreValid() {
        for model in WhisperModel.allCases {
            XCTAssertNotNil(URL(string: model.downloadURL.absoluteString))
        }
    }
}

// MARK: - DefaultPromptLoader tests

final class DefaultPromptLoaderTests: XCTestCase {
    /// The bundled DefaultLLMPrompt.md must be present in the test bundle and non-empty.
    func testDefaultPromptLoadsFromBundle() {
        XCTAssertFalse(DefaultPromptLoader.prompt.isEmpty, "DefaultPromptLoader.prompt must not be empty")
    }

    /// The canonical first-sentence marker ensures the right file was bundled.
    func testDefaultPromptContainsCanonicalSentence() {
        XCTAssertTrue(
            DefaultPromptLoader.prompt.contains("transcription post-processor"),
            "Prompt must identify the assistant as a transcription post-processor"
        )
    }
}

// MARK: - Thinking-tag stripping tests

final class ThinkingTagStrippingTests: XCTestCase {
    private let processor = LLMProcessor()

    /// A single think block wrapping reasoning is stripped, leaving only the answer.
    func testThinkingTagsStrippedFromSimpleResponse() {
        let input = "<think>reasoning here</think>actual answer"
        let result = processor.stripThinkingTags(input)
        XCTAssertEqual(result, "actual answer")
    }

    /// Multiline content inside think tags and multiple think blocks are all removed.
    func testThinkingTagsStrippedFromMultilineResponse() {
        let input = "<think>line1\nline2</think>foo<think>more</think>bar"
        let result = processor.stripThinkingTags(input)
        XCTAssertEqual(result, "foobar")
    }

    /// Input with no think tags is returned unchanged.
    func testNoThinkingTagsReturnedUnchanged() {
        let input = "clean response without any tags"
        let result = processor.stripThinkingTags(input)
        XCTAssertEqual(result, input)
    }
}

// MARK: - ChatRequest thinking-flag tests

/// These tests verify the `think` field is correctly included or omitted in the
/// JSON-encoded request body based on provider and settings.
///
/// They access the internal `buildChatRequestBody(provider:model:systemPrompt:text:settings:)`
/// helper via `@testable import`. If the swift-engineer exposes that function with a
/// different signature, adjust the call site here to match.
///
/// The class is `@MainActor` because `AppSettings` uses `@AppStorage` wrappers whose
/// property-setter dispatch is tied to the main thread. Running on the main actor
/// also prevents `UserDefaults` writes from bleeding between tests via async races.
///
/// We also seed `UserDefaults.standard` directly before each test so that the
/// `@AppStorage` wrapper sees a known value regardless of any prior test execution.
@MainActor
final class ChatRequestThinkingFlagTests: XCTestCase {

    private let thinkingKey = "llmThinkingEnabled"

    override func setUp() {
        super.setUp()
        // Ensure a clean slate before each test.
        UserDefaults.standard.removeObject(forKey: thinkingKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: thinkingKey)
    }

    /// Groq provider must never emit `"think"` even when thinking is enabled in settings.
    func testThinkingFlagOmittedForGroq() throws {
        UserDefaults.standard.set(true, forKey: thinkingKey)
        let settings = AppSettings()

        let body = try LLMProcessor().buildChatRequestBody(
            provider: .groq,
            model: "llama-3.3-70b-versatile",
            systemPrompt: "sys",
            text: "hello",
            settings: settings
        )

        let json = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(json.contains("\"think\""), "Groq request must not contain 'think' key")
    }

    /// Ollama provider with thinking enabled must emit `"think":true`.
    func testThinkingFlagPresentForOllama() throws {
        UserDefaults.standard.set(true, forKey: thinkingKey)
        let settings = AppSettings()

        let body = try LLMProcessor().buildChatRequestBody(
            provider: .ollama,
            model: "gemma4:e2b",
            systemPrompt: "sys",
            text: "hello",
            settings: settings
        )

        let json = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(json.contains("\"think\":true") || json.contains("\"think\": true"),
                      "Ollama request with thinking enabled must contain 'think':true")
    }

    /// Ollama provider with thinking disabled must omit `"think"` entirely (encodeIfPresent → nil).
    func testThinkingFlagOmittedWhenDisabled() throws {
        UserDefaults.standard.set(false, forKey: thinkingKey)
        let settings = AppSettings()

        let body = try LLMProcessor().buildChatRequestBody(
            provider: .ollama,
            model: "gemma4:e2b",
            systemPrompt: "sys",
            text: "hello",
            settings: settings
        )

        let json = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(json.contains("\"think\""),
                       "Ollama request with thinking disabled must not contain 'think' key")
    }
}
