import Cocoa

struct TextInjector {
    enum Method {
        case clipboard
        case typing
    }

    static func inject(_ text: String, method: Method = .clipboard) {
        switch method {
        case .clipboard:
            injectViaClipboard(text)
        case .typing:
            injectViaTyping(text)
        }
    }

    // MARK: - Clipboard Method

    private static func injectViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let previousChangeCount = pasteboard.changeCount
        var previousItems: [(NSPasteboard.PasteboardType, Data)] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        previousItems.append((type, data))
                    }
                }
            }
        }

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            if previousItems.isEmpty { return }
            let item = NSPasteboardItem()
            for (type, data) in previousItems {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    private static func simulatePaste() {
        let vKeyCode: CGKeyCode = 9

        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Typing Method

    private static func injectViaTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)

        for char in text {
            var chars = Array(String(char).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
