import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case german = "de"

    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("settings.general.language_system", comment: "")
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

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

enum ModelGroup: String {
    case compact = "Compact"
    case large = "Large"
    case distil = "Distil (Optimized)"
}

enum WhisperModel: String, CaseIterable {
    case tiny = "ggml-tiny"
    case base = "ggml-base"
    case small = "ggml-small"
    case medium = "ggml-medium"
    case largeTurbo = "ggml-large-v3-turbo"
    case largeTurboQ5 = "ggml-large-v3-turbo-q5_0"
    case largeV1 = "ggml-large-v1"
    case largeV2 = "ggml-large-v2"
    case largeV3 = "ggml-large-v3"
    case distilLargeV3 = "ggml-distil-large-v3"
    case distilMediumEn = "ggml-distil-medium.en"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (75 MB)"
        case .base: return "Base (142 MB)"
        case .small: return "Small (466 MB)"
        case .medium: return "Medium (1.5 GB)"
        case .largeTurbo: return "Large v3 Turbo (1.5 GB)"
        case .largeTurboQ5: return "Large v3 Turbo Q5 (950 MB)"
        case .largeV1: return "Large v1 (2.9 GB)"
        case .largeV2: return "Large v2 (2.9 GB)"
        case .largeV3: return "Large v3 (2.9 GB)"
        case .distilLargeV3: return "Distil Large v3 (1.5 GB)"
        case .distilMediumEn: return "Distil Medium English-only (765 MB)"
        }
    }

    var group: ModelGroup {
        switch self {
        case .tiny, .base, .small, .medium, .largeTurboQ5:
            return .compact
        case .largeTurbo, .largeV1, .largeV2, .largeV3:
            return .large
        case .distilLargeV3, .distilMediumEn:
            return .distil
        }
    }

    /// True for models that only support English transcription
    var isEnglishOnly: Bool {
        self == .distilMediumEn
    }

    var filename: String { "\(rawValue).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}

enum LLMProvider: String, CaseIterable {
    case groq = "groq"
    case cerebras = "cerebras"
    case ollama = "ollama"
    case openRouter = "openRouter"

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .ollama: return "Ollama (local)"
        case .openRouter: return "OpenRouter"
        }
    }

    var baseURL: String {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq: return "llama-3.3-70b-versatile"
        case .cerebras: return "llama3.1-8b"
        case .ollama: return "gemma4:e2b"
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct:free"
        }
    }

    var requiresAPIKey: Bool {
        self != .ollama
    }

    var keychainKey: String {
        "llm_api_key_\(rawValue)"
    }
}

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var from: String
    var to: String

    init(id: UUID = UUID(), from: String = "", to: String = "") {
        self.id = id
        self.from = from
        self.to = to
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
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .system
    @AppStorage("customFillerWords") var customFillerWordsRaw: String = ""

    // LLM post-processing
    @AppStorage("llmEnabled") var llmEnabled: Bool = false
    @AppStorage("llmProvider") var llmProvider: LLMProvider = .ollama
    @AppStorage("llmModel") var llmModel: String = ""
    @AppStorage("llmUseDefaultPrompt") var llmUseDefaultPrompt: Bool = true
    @AppStorage("llmCustomPrompt") var llmCustomPrompt: String = ""
    @AppStorage("llmThinkingEnabled") var llmThinkingEnabled: Bool = false
    @AppStorage("llmDictionaryEntriesRaw") private var llmDictionaryEntriesRaw: String = "[]"

    var effectiveLLMModel: String { llmModel.isEmpty ? llmProvider.defaultModel : llmModel }

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

    var llmDictionaryEntries: [DictionaryEntry] {
        get {
            guard let data = llmDictionaryEntriesRaw.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
            else { return [] }
            return entries
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let str = String(data: data, encoding: .utf8)
            else { return }
            llmDictionaryEntriesRaw = str
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
        return parts.isEmpty ? NSLocalizedString("settings.hotkey.not_set", comment: "") : parts.joined(separator: " + ")
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
