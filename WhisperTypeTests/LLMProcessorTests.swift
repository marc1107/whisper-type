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

    /// Entries with an empty `to` would render as `- foo → ` and confuse the
    /// model. They must be dropped just like entries with an empty `from`.
    func testEntriesWithEmptyToFilteredOut() {
        let entries = [
            DictionaryEntry(from: "foo", to: ""),
            DictionaryEntry(from: "valid", to: "Valid"),
        ]
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: entries
        )
        XCTAssertTrue(prompt.contains("valid → Valid"))
        XCTAssertFalse(prompt.contains("foo → "), "Entries with empty `to` must be dropped")
    }

    /// Whitespace-only fields must be treated as empty so leading/trailing
    /// spaces from settings input don't smuggle in malformed lines.
    func testWhitespaceOnlyFieldsFilteredOut() {
        let entries = [
            DictionaryEntry(from: "  ", to: "Something"),
            DictionaryEntry(from: "  spaced  ", to: "  Spaced  "),
        ]
        let prompt = processor.buildSystemPromptFromParts(
            useDefault: false,
            customPrompt: "",
            entries: entries
        )
        XCTAssertTrue(prompt.contains("spaced → Spaced"), "Whitespace must be trimmed")
        XCTAssertFalse(prompt.contains("Something") && prompt.contains("→  Something"),
                       "Whitespace-only `from` must drop the entry")
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

    /// The dictionary-usage guidance section must remain in the bundled prompt so
    /// the model interprets `wrong → right` pairs as context-aware hints rather
    /// than blind find-and-replace.
    func testDefaultPromptIncludesDictionaryGuidance() {
        XCTAssertTrue(
            DefaultPromptLoader.prompt.contains("Using the word corrections dictionary"),
            "Prompt must include the dictionary-usage guidance section"
        )
    }
}

// MARK: - Rate-limit (HTTP 429) handling

final class LLMRateLimitTests: XCTestCase {
    private func response(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    /// A `Retry-After` header in delta-seconds form should be parsed back as the
    /// integer the provider sent.
    func testRetryAfterParsedAsSeconds() {
        let parsed = LLMProcessor.parseRetryAfter(from: response(headers: ["Retry-After": "30"]))
        XCTAssertEqual(parsed, 30)
    }

    /// Missing `Retry-After` returns nil so the caller falls back to the generic
    /// "try again later" message instead of formatting a bogus duration.
    func testRetryAfterMissingReturnsNil() {
        let parsed = LLMProcessor.parseRetryAfter(from: response(headers: [:]))
        XCTAssertNil(parsed)
    }

    /// `LLMError.rateLimited(retryAfter: nil)` must use the generic localized
    /// message — not crash on the `%d` format specifier.
    func testRateLimitedErrorWithoutRetryUsesGenericMessage() {
        let error: LLMError = .rateLimited(retryAfter: nil)
        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty)
        XCTAssertFalse(description.contains("%d"), "Generic message must not leak format specifier")
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
