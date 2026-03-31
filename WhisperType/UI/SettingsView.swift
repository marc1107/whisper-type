import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: appState.settings)
                .tabItem { Label(NSLocalizedString("settings.general", comment: ""), systemImage: "gear") }

            HotkeySettingsTab(settings: appState.settings)
                .tabItem { Label(NSLocalizedString("settings.hotkey", comment: ""), systemImage: "keyboard") }

            TranscriptionSettingsTab(appState: appState)
                .tabItem { Label(NSLocalizedString("settings.transcription", comment: ""), systemImage: "text.bubble") }
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
            Section(NSLocalizedString("settings.general", comment: "")) {
                Toggle(NSLocalizedString("settings.general.launch_at_login", comment: ""), isOn: $settings.launchAtLogin)
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

                Toggle(NSLocalizedString("settings.general.show_overlay", comment: ""), isOn: $settings.showOverlay)

                Picker(NSLocalizedString("settings.general.insertion_method", comment: ""), selection: $settings.insertionMethod) {
                    Text(NSLocalizedString("settings.general.insertion_clipboard", comment: "")).tag(TextInsertionMethod.clipboard)
                    Text(NSLocalizedString("settings.general.insertion_typing", comment: "")).tag(TextInsertionMethod.typing)
                }

                Picker(NSLocalizedString("settings.general.app_language", comment: ""), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: settings.appLanguage) { _, newValue in
                    if newValue == .system {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
                    }
                }

                if settings.appLanguage != .system {
                    Text(NSLocalizedString("settings.general.language_restart_hint", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(NSLocalizedString("settings.permissions", comment: "")) {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityGranted ? .green : .red)
                    Text(String(format: NSLocalizedString("settings.permissions.accessibility", comment: ""),
                                accessibilityGranted
                                    ? NSLocalizedString("settings.permissions.granted", comment: "")
                                    : NSLocalizedString("settings.permissions.missing", comment: "")))
                    Spacer()
                    if !accessibilityGranted {
                        Button(NSLocalizedString("settings.permissions.open", comment: "")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Image(systemName: microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(microphoneGranted ? .green : .red)
                    Text(String(format: NSLocalizedString("settings.permissions.microphone", comment: ""),
                                microphoneGranted
                                    ? NSLocalizedString("settings.permissions.granted", comment: "")
                                    : NSLocalizedString("settings.permissions.missing", comment: "")))
                    Spacer()
                    if !microphoneGranted {
                        Button(NSLocalizedString("settings.permissions.open", comment: "")) {
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
            Section(NSLocalizedString("settings.hotkey.shortcut", comment: "")) {
                HotkeyRecorderView(settings: settings)
            }

            Section(NSLocalizedString("settings.hotkey.mode", comment: "")) {
                Picker(NSLocalizedString("settings.hotkey.recording_mode", comment: ""), selection: $settings.hotkeyMode) {
                    Text(NSLocalizedString("settings.hotkey.push_to_talk", comment: "")).tag(HotkeyMode.pushToTalk)
                    Text(NSLocalizedString("settings.hotkey.toggle", comment: "")).tag(HotkeyMode.toggle)
                }
                .pickerStyle(.radioGroup)
            }

            Section(NSLocalizedString("settings.hotkey.recording", comment: "")) {
                HStack {
                    Text(NSLocalizedString("settings.hotkey.max_duration", comment: ""))
                    TextField(NSLocalizedString("settings.hotkey.seconds", comment: ""), value: $settings.maxRecordingDuration, format: .number)
                        .frame(width: 80)
                    Text(NSLocalizedString("settings.hotkey.seconds", comment: ""))
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
            Section(NSLocalizedString("settings.transcription.model", comment: "")) {
                Picker(NSLocalizedString("settings.transcription.whisper_model", comment: ""), selection: Binding(
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
                        Button(NSLocalizedString("settings.transcription.cancel", comment: "")) {
                            appState.modelManager.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if !settings.isModelDownloaded(settings.selectedModel) {
                    Button(NSLocalizedString("settings.transcription.download_model", comment: "")) {
                        Task {
                            try? await appState.modelManager.downloadModel(settings.selectedModel)
                            await appState.loadSelectedModel()
                        }
                    }
                } else {
                    HStack {
                        if appState.isModelLoaded {
                            Label(NSLocalizedString("settings.transcription.loaded", comment: ""), systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("settings.transcription.load_model", comment: "")) {
                                Task { await appState.loadSelectedModel() }
                            }
                        }
                        Spacer()
                        Button(NSLocalizedString("settings.transcription.delete", comment: ""), role: .destructive) {
                            try? appState.modelManager.deleteModel(settings.selectedModel)
                            appState.isModelLoaded = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section(NSLocalizedString("settings.transcription.language", comment: "")) {
                Picker(NSLocalizedString("settings.transcription.language", comment: ""), selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    Text(NSLocalizedString("settings.transcription.language_auto", comment: "")).tag(InputLanguage.auto)
                    Text(NSLocalizedString("settings.transcription.language_german", comment: "")).tag(InputLanguage.german)
                    Text(NSLocalizedString("settings.transcription.language_english", comment: "")).tag(InputLanguage.english)
                }
            }

            Section(NSLocalizedString("settings.transcription.postprocessing", comment: "")) {
                Toggle(NSLocalizedString("settings.transcription.remove_fillers", comment: ""), isOn: Binding(
                    get: { settings.fillerFilterEnabled },
                    set: { settings.fillerFilterEnabled = $0 }
                ))

                if settings.fillerFilterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("settings.transcription.custom_fillers", comment: ""))
                            .font(.caption)
                        HStack {
                            TextField(NSLocalizedString("settings.transcription.new_filler", comment: ""), text: $newFillerWord)
                                .textFieldStyle(.roundedBorder)
                            Button(NSLocalizedString("settings.transcription.add", comment: "")) {
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
