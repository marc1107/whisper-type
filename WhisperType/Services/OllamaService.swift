import Foundation

@MainActor
final class OllamaService: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isPulling: Bool = false
    @Published var pullProgress: Double = 0
    @Published var availableModels: [String] = []
    @Published var lastError: String?

    private let baseURL: URL
    private var pullTask: Task<Void, Error>?

    nonisolated init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    func detect() async {
        let url = baseURL.appendingPathComponent("api/tags")
        let request = URLRequest(url: url)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isInstalled = false
                availableModels = []
                return
            }
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            isInstalled = true
            availableModels = decoded.models.map { $0.name }
        } catch {
            isInstalled = false
            availableModels = []
        }
    }

    func pullModelIfMissing(_ name: String) async throws {
        guard !availableModels.contains(name) else { return }
        try await pullModel(name)
    }

    func pullModel(_ name: String) async throws {
        isPulling = true
        pullProgress = 0
        lastError = nil

        defer {
            isPulling = false
        }

        let pullURL = baseURL.appendingPathComponent("api/pull")
        let task = Task.detached<Void> { [weak self] in
            guard let self else { return }

            var request = URLRequest(url: pullURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = OllamaPullRequest(name: name, stream: true)
            request.httpBody = try JSONEncoder().encode(body)

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw OllamaError.unexpectedResponse
            }

            for try await line in asyncBytes.lines {
                let progress = self.parseProgress(from: line)
                if let progress {
                    await MainActor.run { self.pullProgress = progress }
                }

                if let data = line.data(using: .utf8),
                   let status = try? JSONDecoder().decode(OllamaPullStatus.self, from: data),
                   status.status == "success" {
                    await MainActor.run {
                        self.pullProgress = 1.0
                    }
                    await self.detect()
                    return
                }
            }
        }

        pullTask = task
        try await task.value
    }

    func cancelPull() {
        pullTask?.cancel()
        pullTask = nil
        isPulling = false
    }

    nonisolated func parseProgress(from line: String) -> Double? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONDecoder().decode(OllamaPullProgress.self, from: data),
              let completed = obj.completed,
              let total = obj.total,
              total > 0 else {
            return nil
        }
        return Double(completed) / Double(total)
    }
}

// MARK: - Supporting Types

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
}

private struct OllamaPullRequest: Encodable {
    let name: String
    let stream: Bool
}

private struct OllamaPullStatus: Decodable {
    let status: String
}

private struct OllamaPullProgress: Decodable {
    let status: String?
    let completed: Int?
    let total: Int?
}

enum OllamaError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return NSLocalizedString("error.ollama.unexpected_response", comment: "")
        }
    }
}
