import Foundation

enum LLMError: LocalizedError {
    case emptyAPIKey
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return NSLocalizedString("error.llm.empty_api_key", comment: "")
        case .networkError(let error):
            return String(format: NSLocalizedString("error.llm.network", comment: ""), error.localizedDescription)
        case .invalidResponse(let code):
            return String(format: NSLocalizedString("error.llm.invalid_response", comment: ""), code)
        case .decodingError:
            return NSLocalizedString("error.llm.decoding", comment: "")
        case .emptyResult:
            return NSLocalizedString("error.llm.empty_result", comment: "")
        }
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    // swiftlint:disable:next discouraged_optional_boolean
    let think: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(max_tokens, forKey: .max_tokens)
        try container.encodeIfPresent(think, forKey: .think)
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, max_tokens, think
    }
}

private struct ChatResponseMessage: Decodable {
    let content: String
}

private struct ChatResponseChoice: Decodable {
    let message: ChatResponseMessage
}

private struct ChatResponse: Decodable {
    let choices: [ChatResponseChoice]
}

enum DefaultPromptLoader {
    static let prompt: String = {
        guard let url = Bundle.main.url(forResource: "DefaultLLMPrompt", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("DefaultLLMPrompt.md missing from bundle")
            return ""
        }
        return text
    }()
}

struct LLMRequestContext: Sendable {
    let useDefaultPrompt: Bool
    let customPrompt: String
    let dictionary: [DictionaryEntry]
    let thinkingEnabled: Bool
    let model: String
    let provider: LLMProvider
}

final class LLMProcessor: @unchecked Sendable {
    private let lock = NSLock()

    func process(_ text: String, settings: AppSettings) async throws -> String {
        let context = LLMRequestContext(
            useDefaultPrompt: settings.llmUseDefaultPrompt,
            customPrompt: settings.llmCustomPrompt,
            dictionary: settings.llmDictionaryEntries,
            thinkingEnabled: settings.llmThinkingEnabled,
            model: settings.effectiveLLMModel,
            provider: settings.llmProvider
        )
        return try await process(text: text, context: context)
    }

    func process(text: String, context: LLMRequestContext) async throws -> String {
        let provider = context.provider
        let modelName = context.model
        let systemPrompt = buildSystemPromptFromParts(
            useDefault: context.useDefaultPrompt,
            customPrompt: context.customPrompt,
            entries: context.dictionary
        )
        let apiKey = try resolvedAPIKey(for: provider)
        // Emit think: true only when Ollama + thinking enabled; nil → key omitted.
        // swiftlint:disable:next discouraged_optional_boolean
        let thinkFlag: Bool? = (provider == .ollama && context.thinkingEnabled) ? true : nil
        let urlRequest = try buildRequest(
            provider: provider,
            model: modelName,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            text: text,
            think: thinkFlag
        )

        let (data, response) = try await performRequest(urlRequest)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw LLMError.invalidResponse(httpResponse.statusCode)
        }

        return try extractResult(from: data)
    }

    func buildSystemPrompt(settings: AppSettings) -> String {
        buildSystemPromptFromParts(
            useDefault: settings.llmUseDefaultPrompt,
            customPrompt: settings.llmCustomPrompt,
            entries: settings.llmDictionaryEntries
        )
    }

    func buildSystemPromptFromParts(
        useDefault: Bool,
        customPrompt: String,
        entries: [DictionaryEntry]
    ) -> String {
        var parts: [String] = []

        if useDefault {
            parts.append(DefaultPromptLoader.prompt)
        }

        let trimmedCustom = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            parts.append(trimmedCustom)
        }

        if !entries.isEmpty {
            let lines = entries
                .filter { !$0.from.isEmpty }
                .map { "- \($0.from) → \($0.to)" }
                .joined(separator: "\n")
            if !lines.isEmpty {
                parts.append("Word corrections dictionary (always apply these):\n\(lines)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func resolvedAPIKey(for provider: LLMProvider) throws -> String {
        guard provider.requiresAPIKey else { return "" }
        let key = KeychainHelper.load(key: provider.keychainKey) ?? ""
        guard !key.isEmpty else { throw LLMError.emptyAPIKey }
        return key
    }

    private func buildRequest(
        provider: LLMProvider,
        model: String,
        apiKey: String,
        systemPrompt: String,
        text: String,
        // swiftlint:disable:next discouraged_optional_boolean
        think: Bool? = nil
    ) throws -> URLRequest {
        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: text),
            ],
            temperature: 0.1,
            max_tokens: 2048,
            think: think
        )

        var request = URLRequest(url: URL(string: "\(provider.baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LLMError.networkError(error)
        }
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }
    }

    private func extractResult(from data: Data) throws -> String {
        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw LLMError.decodingError
        }
        var result = chatResponse.choices.first?.message.content ?? ""
        result = stripThinkingTags(result)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResult }
        return trimmed
    }

    func stripThinkingTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Builds and encodes the chat request body. Exposed for testability.
    func buildChatRequestBody(
        provider: LLMProvider,
        model: String,
        systemPrompt: String,
        text: String,
        settings: AppSettings
    ) throws -> Data {
        // Emit `think: true` only for Ollama with thinking enabled.
        // nil → key omitted via encodeIfPresent; false would encode as "think":false
        // which is unnecessary noise for providers that don't support the field.
        // swiftlint:disable:next discouraged_optional_boolean
        let thinkFlag: Bool? = (provider == .ollama && settings.llmThinkingEnabled) ? true : nil
        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: text),
            ],
            temperature: 0.1,
            max_tokens: 2048,
            think: thinkFlag
        )
        return try JSONEncoder().encode(body)
    }
}
