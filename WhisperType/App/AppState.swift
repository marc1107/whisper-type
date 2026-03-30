import Combine
import Foundation
import SwiftUI

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case injecting
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastTranscription: String = ""

    let settings = AppSettings.shared
    let audioRecorder = AudioRecorder()
    let whisperEngine = WhisperEngine()
    let modelManager = ModelManager()
    let hotkeyManager = HotkeyManager()
    let overlayController = OverlayWindowController()

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

        // Observe status changes for overlay
        $status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self, self.settings.showOverlay else { return }
                switch newStatus {
                case .idle:
                    self.overlayController.hide()
                case .recording, .transcribing, .injecting, .error:
                    self.overlayController.show(status: newStatus)
                }
            }
            .store(in: &cancellables)

        Task {
            await loadSelectedModel()
        }
    }

    func loadSelectedModel() async {
        let model = settings.selectedModel
        guard settings.isModelDownloaded(model) else { return }
        let path = settings.modelPath(for: model).path
        do {
            try whisperEngine.loadModel(at: path)
        } catch {
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

        guard whisperEngine.isModelLoaded else {
            setError("Kein Whisper-Modell geladen. Bitte zuerst ein Modell herunterladen.")
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

        let language = settings.language.rawValue
        let engine = whisperEngine
        let fillerEnabled = settings.fillerFilterEnabled
        let customFillers = settings.customFillerWords
        let insertionMethod = settings.insertionMethod

        Task.detached { [weak self] in
            do {
                let rawText = try engine.transcribe(
                    samples: samples,
                    language: language == "auto" ? nil : language
                )

                let processor = TextPostProcessor(
                    enabled: fillerEnabled,
                    customFillerWords: customFillers
                )
                let processedText = processor.process(rawText)

                await MainActor.run {
                    guard let self else { return }
                    self.lastTranscription = processedText
                    guard !processedText.isEmpty else {
                        self.status = .idle
                        return
                    }
                    self.status = .injecting
                    TextInjector.inject(
                        processedText,
                        method: insertionMethod == .clipboard ? .clipboard : .typing
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.status == .injecting {
                            self.status = .idle
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self?.setError(error.localizedDescription)
                }
            }
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
}
