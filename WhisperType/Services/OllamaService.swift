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
        let task = Task<Void, Error>.detached { [weak self] in
            guard let self else { return }
            try await self.runPullStream(name: name, url: pullURL)
        }

        pullTask = task
        do {
            try await task.value
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    nonisolated private func runPullStream(name: String, url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaPullRequest(name: name, stream: true))

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.unexpectedResponse
        }

        var sawSuccess = false
        var lastErrorStatus: String?

        for try await line in asyncBytes.lines {
            if let progress = parseProgress(from: line) {
                await MainActor.run { self.pullProgress = progress }
            }
            guard let data = line.data(using: .utf8),
                  let status = try? JSONDecoder().decode(OllamaPullStatus.self, from: data) else { continue }

            if status.status == "success" {
                sawSuccess = true
                await MainActor.run { self.pullProgress = 1.0 }
                await detect()
                return
            }
            if status.status.lowercased().hasPrefix("error") {
                lastErrorStatus = status.status
            }
        }

        // Stream closed without ever emitting `"status":"success"`.
        // Treat it as a failed pull so callers don't believe the model arrived.
        guard sawSuccess else {
            throw OllamaError.pullIncomplete(lastStatus: lastErrorStatus)
        }
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
    case pullIncomplete(lastStatus: String?)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return NSLocalizedString("error.ollama.unexpected_response", comment: "")
        case .pullIncomplete(let lastStatus):
            if let lastStatus, !lastStatus.isEmpty {
                return String(format: NSLocalizedString("error.ollama.pull_incomplete_with_status", comment: ""), lastStatus)
            }
            return NSLocalizedString("error.ollama.pull_incomplete", comment: "")
        }
    }
}
