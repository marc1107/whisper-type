import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    let settings = AppSettings.shared

    func ensureModelsDirectoryExists() throws {
        let dir = settings.modelsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func downloadModel(_ model: WhisperModel) async throws {
        try ensureModelsDirectoryExists()

        let destination = settings.modelPath(for: model)
        if FileManager.default.fileExists(atPath: destination.path) { return }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        defer {
            isDownloading = false
            progressObservation = nil
        }

        let (tempURL, _) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: model.downloadURL) { url, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url, let response = response {
                    continuation.resume(returning: (url, response))
                } else {
                    continuation.resume(throwing: ModelManagerError.downloadFailed)
                }
            }
            self.downloadTask = task
            self.progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
            task.resume()
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    func deleteModel(_ model: WhisperModel) throws {
        let path = settings.modelPath(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    func localModels() -> [WhisperModel] {
        WhisperModel.allCases.filter { settings.isModelDownloaded($0) }
    }
}

enum ModelManagerError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Modell-Download fehlgeschlagen."
        }
    }
}
