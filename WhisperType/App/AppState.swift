import Combine
import Foundation
import SwiftUI

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case preparingModel
    case postProcessing
    case injecting
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastTranscription: String = ""
    @Published var isModelLoaded: Bool = false
    @Published var isPreparingModel: Bool = false

    let settings = AppSettings.shared
    let audioRecorder = AudioRecorder()
    let whisperEngine = WhisperEngine()
    let modelManager = ModelManager()
    let hotkeyManager = HotkeyManager()
    let overlayController = OverlayWindowController()
    let llmProcessor = LLMProcessor()
    let ollamaService = OllamaService()

    private var recordingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var isRecording: Bool { status == .recording }

    func setup() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyDown()
            }
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyUp()
            }
        }

        do {
            try hotkeyManager.start()
        } catch {
            setError(error.localizedDescription)
        }

        $status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self, self.settings.showOverlay else { return }
                switch newStatus {
                case .idle:
                    self.overlayController.hide()
                case .recording, .transcribing, .preparingModel, .postProcessing, .injecting, .error:
                    self.overlayController.show(status: newStatus)
                }
            }
            .store(in: &cancellables)

        Task {
            await loadSelectedModel()
        }

        Task {
            await ollamaService.detect()
            if settings.llmProvider == .ollama && settings.llmEnabled && ollamaService.isInstalled {
                try? await ollamaService.pullModelIfMissing(settings.effectiveLLMModel)
            }
        }
    }

    func loadSelectedModel() async {
        let model = settings.selectedModel
        guard settings.isModelDownloaded(model) else {
            isModelLoaded = false
            return
        }
        let path = settings.modelPath(for: model).path
        isPreparingModel = true
        do {
            try await Task.detached(priority: .userInitiated) { [engine = whisperEngine] in
                try engine.loadModel(at: path)
            }.value
            isPreparingModel = false
            isModelLoaded = true
        } catch {
            isPreparingModel = false
            isModelLoaded = false
            setError(error.localizedDescription)
        }
    }

    func handleHotkeyDown() {
        switch settings.hotkeyMode {
        case .pushToTalk:
            startRecording()
        case .toggle:
            if status == .recording {
                stopRecordingAndTranscribe()
            } else if status == .idle {
                startRecording()
            }
        }
    }

    func handleHotkeyUp() {
        if settings.hotkeyMode == .pushToTalk && status == .recording {
            stopRecordingAndTranscribe()
        }
    }

    private func startRecording() {
        guard status == .idle || {
            if case .error = status { return true }
            return false
        }() else { return }

        guard isModelLoaded else {
            setError(NSLocalizedString("error.no_model", comment: ""))
            return
        }

        do {
            try audioRecorder.startRecording()
            status = .recording

            recordingTimer = Timer.scheduledTimer(
                withTimeInterval: settings.maxRecordingDuration,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopRecordingAndTranscribe()
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() {
        guard status == .recording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil

        let samples = audioRecorder.stopRecording()
        guard !samples.isEmpty else {
            status = .idle
            return
        }

        status = .transcribing

        // Force English for English-only distil models
        let selectedModel = settings.selectedModel
        let rawLanguage = settings.language.rawValue
        let effectiveLanguage: String? = selectedModel.isEnglishOnly ? "en" : (rawLanguage == "auto" ? nil : rawLanguage)

        let engine = whisperEngine
        let fillerEnabled = settings.fillerFilterEnabled
        let customFillers = settings.customFillerWords
        let insertionMethod = settings.insertionMethod
        let llmEnabled = settings.llmEnabled
        let llmProcessor = self.llmProcessor
        let llmContext = LLMRequestContext(
            useDefaultPrompt: settings.llmUseDefaultPrompt,
            customPrompt: settings.llmCustomPrompt,
            dictionary: settings.llmDictionaryEntries,
            thinkingEnabled: settings.llmThinkingEnabled,
            model: settings.effectiveLLMModel,
            provider: settings.llmProvider
        )

        Task.detached { [weak self] in
            do {
                let rawText = try engine.transcribe(samples: samples, language: effectiveLanguage)
                let processedText = TextPostProcessor(enabled: fillerEnabled, customFillerWords: customFillers).process(rawText)
                let finalText = await self?.applyLLMIfEnabled(
                    text: processedText,
                    llmEnabled: llmEnabled,
                    llmProcessor: llmProcessor,
                    llmContext: llmContext
                ) ?? processedText

                await MainActor.run {
                    guard let self else { return }
                    self.lastTranscription = finalText
                    guard !finalText.isEmpty else { self.status = .idle; return }
                    self.status = .injecting
                    TextInjector.inject(finalText, method: insertionMethod == .clipboard ? .clipboard : .typing)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.status == .injecting { self.status = .idle }
                    }
                }
            } catch {
                await MainActor.run { self?.setError(error.localizedDescription) }
            }
        }
    }

    nonisolated private func applyLLMIfEnabled(
        text: String,
        llmEnabled: Bool,
        llmProcessor: LLMProcessor,
        llmContext: LLMRequestContext
    ) async -> String {
        guard llmEnabled else { return text }
        let provider = llmContext.provider
        let apiKey = provider.requiresAPIKey
            ? (KeychainHelper.load(key: provider.keychainKey) ?? "")
            : ""
        guard !provider.requiresAPIKey || !apiKey.isEmpty else { return text }
        await MainActor.run { self.status = .postProcessing }
        do {
            let enhanced = try await llmProcessor.process(text: text, context: llmContext)
            return enhanced.isEmpty ? text : enhanced
        } catch let error as LLMError {
            if case .rateLimited = error {
                await MainActor.run { self.setTransientError(error.localizedDescription) }
            }
            return text
        } catch {
            return text
        }
    }

    private func setError(_ message: String) {
        status = .error(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if case .error = self?.status {
                self?.status = .idle
            }
        }
    }

    /// Surfaces a transient error message without parking the state machine in `.error` —
    /// the next dictation can start immediately because `idle` is restored after 4 s.
    private func setTransientError(_ message: String) {
        status = .error(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            if case .error(let current) = self.status, current == message {
                self.status = .idle
            }
        }
    }
}
