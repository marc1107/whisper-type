import XCTest
@testable import WhisperType

/// Verifies every `@AppStorage`-backed setting round-trips through `UserDefaults`.
/// These tests are the safety net for the bug in #10 where Picker bindings appeared
/// to "revert" because the wrapping view never observed `AppSettings`.
///
/// The shared-singleton tests touch `UserDefaults.standard` (that's where
/// `@AppStorage` writes), so `setUp` snapshots every key the suite mutates and
/// `tearDown` restores it — even if a test aborts mid-flight.
final class AppSettingsPersistenceTests: XCTestCase {
    private let suiteName = "WhisperTypeSettingsTests"
    private var defaults: UserDefaults!

    private static let sharedKeys: [String] = [
        "selectedModel",
        "language",
        "appLanguage",
        "customFillerWords",
        "llmDictionaryEntriesRaw",
        "llmModel",
        "llmProvider",
    ]
    private var sharedSnapshot: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)

        sharedSnapshot = Self.sharedKeys.reduce(into: [:]) { snapshot, key in
            if let value = UserDefaults.standard.object(forKey: key) {
                snapshot[key] = value
            }
        }
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil

        for key in Self.sharedKeys {
            if let value = sharedSnapshot[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        sharedSnapshot = [:]
        super.tearDown()
    }

    // MARK: - Direct UserDefaults round-trips for the keys @AppStorage uses

    func testInputLanguagePersistsRawValue() {
        defaults.set(InputLanguage.english.rawValue, forKey: "language")
        let loaded = defaults.string(forKey: "language").flatMap(InputLanguage.init(rawValue:))
        XCTAssertEqual(loaded, .english)
    }

    func testWhisperModelPersistsRawValue() {
        defaults.set(WhisperModel.distilLargeV3.rawValue, forKey: "selectedModel")
        let loaded = defaults.string(forKey: "selectedModel").flatMap(WhisperModel.init(rawValue:))
        XCTAssertEqual(loaded, .distilLargeV3)
    }

    func testAppLanguagePersistsRawValue() {
        defaults.set(AppLanguage.german.rawValue, forKey: "appLanguage")
        let loaded = defaults.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:))
        XCTAssertEqual(loaded, .german)
    }

    func testHotkeyModePersistsRawValue() {
        defaults.set(HotkeyMode.toggle.rawValue, forKey: "hotkeyMode")
        let loaded = defaults.string(forKey: "hotkeyMode").flatMap(HotkeyMode.init(rawValue:))
        XCTAssertEqual(loaded, .toggle)
    }

    func testInsertionMethodPersistsRawValue() {
        defaults.set(TextInsertionMethod.typing.rawValue, forKey: "insertionMethod")
        let loaded = defaults.string(forKey: "insertionMethod").flatMap(TextInsertionMethod.init(rawValue:))
        XCTAssertEqual(loaded, .typing)
    }

    // MARK: - AppSettings shared instance round-trips

    func testAppSettingsSelectedModelRoundTrip() {
        let settings = AppSettings.shared

        for model in [WhisperModel.tiny, .base, .largeTurbo, .distilLargeV3] {
            settings.selectedModel = model
            XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedModel"), model.rawValue,
                           "selectedModel did not write through to UserDefaults for \(model)")
            XCTAssertEqual(settings.selectedModel, model,
                           "selectedModel did not read back the value just written for \(model)")
        }
    }

    func testAppSettingsLanguageRoundTrip() {
        let settings = AppSettings.shared

        for language in InputLanguage.allCases {
            settings.language = language
            XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), language.rawValue)
            XCTAssertEqual(settings.language, language)
        }
    }

    func testAppSettingsAppLanguageRoundTrip() {
        let settings = AppSettings.shared

        for language in AppLanguage.allCases {
            settings.appLanguage = language
            XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), language.rawValue)
            XCTAssertEqual(settings.appLanguage, language)
        }
    }

    // MARK: - Custom filler words & dictionary entries (computed wrappers)

    func testCustomFillerWordsRoundTripThroughCSV() {
        let settings = AppSettings.shared

        settings.customFillerWords = ["Also", "halt", "  EBEN  "]
        XCTAssertEqual(settings.customFillerWords, ["also", "halt", "eben"])
    }

    func testLLMDictionaryEntriesRoundTripThroughJSON() {
        let settings = AppSettings.shared

        let entries = [
            DictionaryEntry(from: "ki", to: "AI"),
            DictionaryEntry(from: "vs code", to: "VS Code"),
        ]
        settings.llmDictionaryEntries = entries
        XCTAssertEqual(settings.llmDictionaryEntries.map(\.from), ["ki", "vs code"])
        XCTAssertEqual(settings.llmDictionaryEntries.map(\.to), ["AI", "VS Code"])
    }

    // MARK: - Effective LLM model fallback

    func testEffectiveLLMModelFallsBackToProviderDefault() {
        let settings = AppSettings.shared

        settings.llmProvider = .groq
        settings.llmModel = ""
        XCTAssertEqual(settings.effectiveLLMModel, LLMProvider.groq.defaultModel)

        settings.llmModel = "custom-model"
        XCTAssertEqual(settings.effectiveLLMModel, "custom-model")
    }
}
