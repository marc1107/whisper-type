import Foundation
import SwiftUI

enum HotkeyMode: String, CaseIterable {
    case pushToTalk = "pushToTalk"
    case toggle = "toggle"
}

enum InputLanguage: String, CaseIterable {
    case auto = "auto"
    case german = "de"
    case english = "en"
}

enum TextInsertionMethod: String, CaseIterable {
    case clipboard = "clipboard"
    case typing = "typing"
}

enum WhisperModel: String, CaseIterable {
    case tiny = "ggml-tiny"
    case base = "ggml-base"
    case small = "ggml-small"
    case medium = "ggml-medium"
    case largeTurbo = "ggml-large-v3-turbo"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (75 MB)"
        case .base: return "Base (142 MB)"
        case .small: return "Small (466 MB)"
        case .medium: return "Medium (1.5 GB)"
        case .largeTurbo: return "Large v3 Turbo (1.5 GB)"
        }
    }

    var filename: String { "\(rawValue).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("hotkeyMode") var hotkeyMode: HotkeyMode = .pushToTalk
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 2 // 'd' key
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 524576 // Option key CGEventFlags raw
    @AppStorage("selectedModel") var selectedModel: WhisperModel = .largeTurbo
    @AppStorage("language") var language: InputLanguage = .auto
    @AppStorage("fillerFilterEnabled") var fillerFilterEnabled: Bool = true
    @AppStorage("showOverlay") var showOverlay: Bool = true
    @AppStorage("insertionMethod") var insertionMethod: TextInsertionMethod = .clipboard
    @AppStorage("maxRecordingDuration") var maxRecordingDuration: Double = 120
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("customFillerWords") var customFillerWordsRaw: String = ""

    var customFillerWords: [String] {
        get {
            customFillerWordsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        }
        set {
            customFillerWordsRaw = newValue.joined(separator: ",")
        }
    }

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WhisperType/Models", isDirectory: true)
    }

    func modelPath(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.filename)
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }
}
