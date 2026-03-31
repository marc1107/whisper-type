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

            if appState.modelManager.isDownloading {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: NSLocalizedString("menu.downloading_model", comment: ""), appState.settings.selectedModel.displayName))
                        .font(.caption)
                    ProgressView(value: appState.modelManager.downloadProgress)
                        .progressViewStyle(.linear)
                    Text("\(Int(appState.modelManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if !appState.isModelLoaded {
                Divider()
                Button(String(format: NSLocalizedString("menu.download_model", comment: ""), appState.settings.selectedModel.displayName)) {
                    Task {
                        do {
                            try await appState.modelManager.downloadModel(appState.settings.selectedModel)
                            await appState.loadSelectedModel()
                        } catch {}
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
                Text(NSLocalizedString("menu.settings", comment: ""))
            }

            Button(NSLocalizedString("menu.quit", comment: "")) {
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
            if appState.modelManager.isDownloading {
                return NSLocalizedString("status.downloading_model", comment: "")
            }
            return appState.isModelLoaded
                ? NSLocalizedString("status.ready", comment: "")
                : NSLocalizedString("status.no_model", comment: "")
        case .recording: return NSLocalizedString("status.recording", comment: "")
        case .transcribing: return NSLocalizedString("status.transcribing", comment: "")
        case .injecting: return NSLocalizedString("status.injecting", comment: "")
        case .error(let msg): return msg
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle:
            if appState.modelManager.isDownloading { return .orange }
            return appState.isModelLoaded ? .green : .orange
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
