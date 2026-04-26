import XCTest
@testable import WhisperType

/// These tests verify the `think` field is correctly included or omitted in the
/// JSON-encoded request body based on provider and settings.
///
/// They access the internal `buildChatRequestBody(provider:model:systemPrompt:text:settings:)`
/// helper via `@testable import`.
///
/// The class is `@MainActor` because `AppSettings` uses `@AppStorage` wrappers
/// whose property-setter dispatch is tied to the main thread.
@MainActor
final class ChatRequestThinkingFlagTests: XCTestCase {

    private let thinkingKey = "llmThinkingEnabled"

    override func setUp() {
        super.setUp()
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
