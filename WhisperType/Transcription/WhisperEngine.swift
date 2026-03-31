import Foundation

final class WhisperEngine: @unchecked Sendable {
    private var context: OpaquePointer?
    private let lock = NSLock()

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return context != nil
    }

    func loadModel(at path: String) throws {
        lock.lock()
        defer { lock.unlock() }

        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true
        contextParams.flash_attn = true

        guard let ctx = whisper_init_from_file_with_params(path, contextParams) else {
            throw WhisperError.modelLoadFailed
        }
        context = ctx
    }

    func transcribe(samples: [Float], language: String? = nil, translate: Bool = false) throws -> String {
        lock.lock()
        guard let ctx = context else {
            lock.unlock()
            throw WhisperError.modelNotLoaded
        }
        lock.unlock()

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
        params.translate = translate
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false

        var languageCString: UnsafeMutablePointer<CChar>?
        if let lang = language, lang != "auto" {
            languageCString = strdup(lang)
            params.language = UnsafePointer(languageCString)
        }
        defer { free(languageCString) }

        let result = samples.withUnsafeBufferPointer { bufferPtr in
            whisper_full(ctx, params, bufferPtr.baseAddress, Int32(samples.count))
        }

        guard result == 0 else {
            throw WhisperError.transcriptionFailed
        }

        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let segmentText = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segmentText)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unloadModel() {
        lock.lock()
        defer { lock.unlock() }
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }
}

enum WhisperError: LocalizedError {
    case modelLoadFailed
    case modelNotLoaded
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return NSLocalizedString("error.model_load_failed", comment: "")
        case .modelNotLoaded: return NSLocalizedString("error.model_not_loaded", comment: "")
        case .transcriptionFailed: return NSLocalizedString("error.transcription_failed", comment: "")
        }
    }
}
