import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var didSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
            }

            if !appState.whisperEngine.isModelLoaded {
                Divider()
                if appState.modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lade Modell herunter...")
                            .font(.caption)
                        ProgressView(value: appState.modelManager.downloadProgress)
                            .progressViewStyle(.linear)
                        Text("\(Int(appState.modelManager.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Modell herunterladen (\(appState.settings.selectedModel.displayName))") {
                        Task {
                            do {
                                try await appState.modelManager.downloadModel(appState.settings.selectedModel)
                                await appState.loadSelectedModel()
                            } catch {
                                // Error shown via model manager
                            }
                        }
                    }
                }
            }

            if !appState.lastTranscription.isEmpty {
                Divider()
                Text(truncatedTranscription)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundColor(.secondary)
            }

            Divider()

            SettingsLink {
                Text("Einstellungen...")
            }

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .task {
            guard !didSetup else { return }
            didSetup = true
            appState.setup()
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle:
            return appState.whisperEngine.isModelLoaded ? "Bereit" : "Kein Modell geladen"
        case .recording: return "Aufnahme..."
        case .transcribing: return "Transkribiere..."
        case .injecting: return "Füge ein..."
        case .error(let msg): return msg
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return appState.whisperEngine.isModelLoaded ? .green : .orange
        case .recording: return .red
        case .transcribing: return .orange
        case .injecting: return .blue
        case .error: return .red
        }
    }

    private var truncatedTranscription: String {
        let text = appState.lastTranscription
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }
}
