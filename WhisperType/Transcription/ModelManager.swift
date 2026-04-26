import Foundation

/// Lock-protected timestamp gate that decides — without ever touching the
/// MainActor — whether a KVO progress tick is worth dispatching to the UI.
/// Lives outside `ModelManager`'s actor isolation so the observer closure can
/// drop ticks before scheduling any Task at all (the original "spawning a
/// Task per fire" bug — see PR #9 review).
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmit: Date = .distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Returns true at most once per `interval`, plus whenever `isFinal` is set
    /// (so the final 100 % tick is never dropped). Thread-safe.
    func shouldEmit(now: Date, isFinal: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFinal || now.timeIntervalSince(lastEmit) >= interval {
            lastEmit = now
            return true
        }
        return false
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private let throttle = ProgressThrottle(interval: 0.1)

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
            let throttle = self.throttle
            self.progressObservation = task.progress.observe(\.fractionCompleted) { [weak self, throttle] progress, _ in
                let snapshot = progress.fractionCompleted
                guard throttle.shouldEmit(now: Date(), isFinal: snapshot >= 1.0) else { return }
                Task { @MainActor [weak self] in
                    self?.downloadProgress = snapshot
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
        case .downloadFailed: return NSLocalizedString("error.download_failed", comment: "")
        }
    }
}
