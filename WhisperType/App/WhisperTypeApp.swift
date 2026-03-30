import SwiftUI

@main
struct WhisperTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.isRecording ? .red : .primary)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
