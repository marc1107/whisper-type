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
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = -1 // -1 = modifier-only hotkey
    // Fn + Control
    // maskControl(0x40000) | maskSecondaryFn(0x800000)
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0x840000
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

    var hotkeyDisplayString: String {
        let flags = CGEventFlags(rawValue: UInt64(hotkeyModifiers))
        var parts: [String] = []
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        if hotkeyKeyCode >= 0 {
            parts.append(Self.keyCodeToString(UInt16(hotkeyKeyCode)))
        }
        return parts.isEmpty ? "Nicht gesetzt" : parts.joined(separator: " + ")
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let mapping: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Escape",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15",
            118: "F4", 119: "F2", 120: "F1",
            122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
        ]
        return mapping[keyCode] ?? "Key\(keyCode)"
    }
}
