import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: appState.settings)
                .tabItem { Label("Allgemein", systemImage: "gear") }

            HotkeySettingsTab(settings: appState.settings)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            TranscriptionSettingsTab(appState: appState)
                .tabItem { Label("Transkription", systemImage: "text.bubble") }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneGranted = false

    let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Bei Login starten", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            settings.launchAtLogin = !newValue
                        }
                    }

                Toggle("Status-Overlay anzeigen", isOn: $settings.showOverlay)

                Picker("Einfügemethode", selection: $settings.insertionMethod) {
                    Text("Zwischenablage (Cmd+V)").tag(TextInsertionMethod.clipboard)
                    Text("Tastatur-Simulation").tag(TextInsertionMethod.typing)
                }
            }

            Section("Berechtigungen") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityGranted ? .green : .red)
                    Text("Bedienungshilfen: \(accessibilityGranted ? "Erteilt" : "Fehlt")")
                    Spacer()
                    if !accessibilityGranted {
                        Button("Öffnen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Image(systemName: microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(microphoneGranted ? .green : .red)
                    Text("Mikrofon: \(microphoneGranted ? "Erteilt" : "Fehlt")")
                    Spacer()
                    if !microphoneGranted {
                        Button("Öffnen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { checkPermissions() }
        .onReceive(permissionTimer) { _ in checkPermissions() }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }
}

// MARK: - Hotkey Tab

struct HotkeySettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Tastenkombination") {
                HotkeyRecorderView(settings: settings)
            }

            Section("Modus") {
                Picker("Aufnahmemodus", selection: $settings.hotkeyMode) {
                    Text("Push-to-Talk (gedrückt halten)").tag(HotkeyMode.pushToTalk)
                    Text("Toggle (einmal drücken)").tag(HotkeyMode.toggle)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Aufnahme") {
                HStack {
                    Text("Maximale Dauer:")
                    TextField("Sekunden", value: $settings.maxRecordingDuration, format: .number)
                        .frame(width: 80)
                    Text("Sekunden")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Transcription Tab

struct TranscriptionSettingsTab: View {
    @ObservedObject var appState: AppState
    @State private var newFillerWord = ""

    var settings: AppSettings { appState.settings }

    var body: some View {
        Form {
            Section("Modell") {
                Picker("Whisper-Modell", selection: Binding(
                    get: { settings.selectedModel },
                    set: { settings.selectedModel = $0 }
                )) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        HStack {
                            Text(model.displayName)
                            if settings.isModelDownloaded(model) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        .tag(model)
                    }
                }

                if appState.modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ProgressView(value: appState.modelManager.downloadProgress)
                                .progressViewStyle(.linear)
                            Text("\(Int(appState.modelManager.downloadProgress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        Button("Abbrechen") {
                            appState.modelManager.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if !settings.isModelDownloaded(settings.selectedModel) {
                    Button("Modell herunterladen") {
                        Task {
                            try? await appState.modelManager.downloadModel(settings.selectedModel)
                            await appState.loadSelectedModel()
                        }
                    }
                } else {
                    HStack {
                        if appState.isModelLoaded && settings.selectedModel == settings.selectedModel {
                            Label("Geladen", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Modell laden") {
                                Task { await appState.loadSelectedModel() }
                            }
                        }
                        Spacer()
                        Button("Löschen", role: .destructive) {
                            try? appState.modelManager.deleteModel(settings.selectedModel)
                            appState.isModelLoaded = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("Sprache") {
                Picker("Sprache", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    Text("Automatisch").tag(InputLanguage.auto)
                    Text("Deutsch").tag(InputLanguage.german)
                    Text("English").tag(InputLanguage.english)
                }
            }

            Section("Nachbearbeitung") {
                Toggle("Füllwörter entfernen", isOn: Binding(
                    get: { settings.fillerFilterEnabled },
                    set: { settings.fillerFilterEnabled = $0 }
                ))

                if settings.fillerFilterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Eigene Füllwörter:")
                            .font(.caption)
                        HStack {
                            TextField("Neues Füllwort", text: $newFillerWord)
                                .textFieldStyle(.roundedBorder)
                            Button("Hinzufügen") {
                                guard !newFillerWord.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                var words = settings.customFillerWords
                                words.append(newFillerWord.lowercased().trimmingCharacters(in: .whitespaces))
                                settings.customFillerWords = words
                                newFillerWord = ""
                            }
                        }
                        ForEach(settings.customFillerWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button(role: .destructive) {
                                    settings.customFillerWords = settings.customFillerWords.filter { $0 != word }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
